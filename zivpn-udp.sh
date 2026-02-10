#!/bin/bash
# ZIVPN UDP Server + Web UI (Myanmar)
# Features: Renew/Update Button (Date Picker), Auto-Sync, Receipt Export

set -euo pipefail

# ===== Pretty =====
B="\e[1;34m"; G="\e[1;32m"; Y="\e[1;33m"; R="\e[1;31m"; C="\e[1;36m"; M="\e[1;35m"; Z="\e[0m"
LINE="${B}────────────────────────────────────────────────────────${Z}"
say(){ echo -e "$1"; }

echo -e "\n$LINE\n${G}🌟 ZIVPN UDP-KSO (RENEW BUTTON VERSION)${Z}\n$LINE"

# ===== Root check =====
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${R}ဤ script ကို root အဖြစ် run ရပါမယ် (sudo -i)${Z}"
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive

# ===== Basic Setup & Packages =====
say "${Y}📦 Packages တင်နေပါတယ်...${Z}"
apt-get update -y >/dev/null
apt-get install -y curl ufw jq python3 python3-flask iproute2 conntrack ca-certificates openssl >/dev/null

# ===== Paths & Files =====
BIN="/usr/local/bin/zivpn"
CFG="/etc/zivpn/config.json"
USERS="/etc/zivpn/users.json"
ENVF="/etc/zivpn/web.env"
mkdir -p /etc/zivpn

# ===== Download Binary =====
say "${Y}⬇️ ZIVPN binary ကို ဒေါင်းနေပါတယ်...${Z}"
curl -fsSL -o "$BIN" "https://github.com/zahidbd2/udp-zivpn/releases/latest/download/udp-zivpn-linux-amd64"
chmod +x "$BIN"

# ===== SSL Certs =====
if [ ! -f /etc/zivpn/zivpn.crt ]; then
    openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
    -subj "/C=MM/ST=Yangon/L=Yangon/O=KSO/CN=zivpn" \
    -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt" >/dev/null 2>&1
fi

# ===== Web Admin Setup =====
say "${Y}🔒 Web Admin Login သတ်မှတ်ပါ${Z}"
read -r -p "Username: " WEB_USER
read -r -s -p "Password: " WEB_PASS; echo
WEB_SECRET=$(openssl rand -hex 16)

echo "WEB_ADMIN_USER=${WEB_USER}" > "$ENVF"
echo "WEB_ADMIN_PASSWORD=${WEB_PASS}" >> "$ENVF"
echo "WEB_SECRET=${WEB_SECRET}" >> "$ENVF"
chmod 600 "$ENVF"

# ===== Web UI (web.py) - ပြင်ဆင်ပြီးသား Version =====
cat >/etc/zivpn/web.py <<'PY'
import os, json, subprocess, tempfile, hmac, re
from flask import Flask, jsonify, render_template_string, request, redirect, url_for, session, make_response
from datetime import datetime, timedelta

app = Flask(__name__)
app.secret_key = os.environ.get("WEB_SECRET", "kso-secret")

USERS_FILE = "/etc/zivpn/users.json"
CONFIG_FILE = "/etc/zivpn/config.json"
LOGO_URL = "https://raw.githubusercontent.com/KYAWSOEOO8/kso-script/main/icon.png"

# --- UI HTML ---
HTML = """<!doctype html>
<html lang="my"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
<script src="https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js"></script>
<style>
    :root{ --bg:#f0f2f5; --fg:#1e293b; --primary:#2563eb; --ok:#10b981; --warn:#f59e0b; --bad:#ef4444; --card:#fff; --bd:#e2e8f0; --muted:#64748b; }
    body{ font-family:'Segoe UI',sans-serif; background:var(--bg); color:var(--fg); margin:0; padding:15px; display:flex; flex-direction:column; align-items:center; }
    .container{ width:100%; max-width:450px; }
    header{ text-align:center; margin-bottom:15px; }
    .brand img{ width:65px; border-radius:15px; box-shadow:0 4px 10px rgba(0,0,0,0.1); }
    .card{ background:var(--card); border-radius:20px; padding:20px; box-shadow:0 4px 12px rgba(0,0,0,0.05); margin-bottom:15px; }
    .input-grp{ margin-bottom:12px; }
    label{ display:block; font-size:11px; font-weight:800; color:var(--muted); margin-bottom:5px; text-transform:uppercase; }
    input{ width:100%; padding:12px; border:2px solid var(--bd); border-radius:10px; font-size:14px; box-sizing:border-box; }
    .btn-main{ width:100%; padding:14px; background:var(--primary); color:#fff; border:none; border-radius:12px; font-weight:800; cursor:pointer; }
    
    /* User Table/Cards */
    table{ width:100%; border-collapse:separate; border-spacing:0 8px; }
    td{ background:var(--card); padding:12px; border-radius:12px; border:1px solid var(--bd); }
    .status-line{ width:5px; height:40px; border-radius:10px; display:inline-block; margin-right:10px; vertical-align:middle; }
    
    /* Renew Section */
    .action-row{ display:flex; gap:10px; align-items:center; margin-top:10px; }
    .renew-btn-wrapper{ position:relative; overflow:hidden; background:#dbeafe; color:var(--primary); padding:8px 12px; border-radius:8px; font-weight:700; font-size:12px; display:flex; align-items:center; gap:5px; }
    .renew-btn-wrapper input[type="date"]{ position:absolute; left:0; top:0; opacity:0; width:100%; height:100%; cursor:pointer; }
    .del-btn{ color:var(--bad); background:#fee2e2; border:none; padding:8px 12px; border-radius:8px; cursor:pointer; }
</style>
</head>
<body>
<div class="container">
    {% if not authed %}
    <div class="card" style="margin-top:50px; text-align:center;">
        <img src="{{logo}}" style="width:80px; border-radius:20px;">
        <h2>ADMIN LOGIN</h2>
        <form method="post" action="/login">
            <input name="u" placeholder="Username" required style="margin-bottom:10px;">
            <input name="p" type="password" placeholder="Password" required style="margin-bottom:15px;">
            <button class="btn-main">LOGIN</button>
        </form>
    </div>
    {% else %}
    <header>
        <div class="brand"><img src="{{logo}}"><h1>KSO VIP PANEL</h1></div>
        <div style="display:flex; justify-content:center; gap:15px;">
            <a href="https://m.me/kyawsoe.oo.1292019" target="_blank" style="text-decoration:none; color:var(--primary); font-weight:700;">SUPPORT</a>
            <a href="/logout" style="text-decoration:none; color:var(--bad); font-weight:700;">LOGOUT</a>
        </div>
    </header>

    <div class="card">
        <form method="post" action="/add" id="userForm">
            <div style="display:grid; grid-template-columns:1fr 1fr; gap:10px; margin-bottom:10px;">
                <input id="inUser" name="user" placeholder="နာမည်" required>
                <input id="inPass" name="password" placeholder="စကားဝှက်" required>
            </div>
            <input id="inDays" name="expires" type="number" placeholder="ရက်ပေါင်း (ဥပမာ-၃၀)" style="margin-bottom:10px;">
            <button type="button" onclick="handleSave()" class="btn-main">SAVE & DOWNLOAD PNG</button>
        </form>
    </div>

    <div id="receipt" style="position:fixed; left:-9999px; background:white; padding:40px; width:350px; text-align:center; border-radius:20px;">
        <h1 style="color:var(--primary);">KSO VIP</h1>
        <hr>
        <p>Name: <b id="rUser"></b></p>
        <p>Pass: <b id="rPass"></b></p>
        <p>Until: <b id="rDate"></b></p>
        <p style="margin-top:20px; color:var(--ok);">Thank You!</p>
    </div>

    <table>
        {% for u in users %}
        {% set d = u.days_left | int %}
        <tr>
            <td>
                <div class="status-line" style="background:{% if d > 10 %}var(--ok){% elif d > 3 %}var(--warn){% else %}var(--bad){% endif %};"></div>
                <div style="display:inline-block; vertical-align:middle;">
                    <strong style="font-size:16px;">{{u.user}}</strong><br>
                    <small style="color:var(--muted);">{{u.expires}} ({{d}} days left)</small>
                </div>
                <div class="action-row">
                    <form method="post" action="/add" style="margin:0;">
                        <input type="hidden" name="user" value="{{u.user}}">
                        <input type="hidden" name="password" value="{{u.password}}">
                        <div class="renew-btn-wrapper">
                            <i class="fa-solid fa-calendar-plus"></i> သက်တမ်းတိုး
                            <input type="date" name="expires" required onchange="this.form.submit()">
                        </div>
                    </form>
                    <form method="post" action="/delete" style="margin:0;" onsubmit="return confirm('ဖျက်မှာလား?')">
                        <input type="hidden" name="user" value="{{u.user}}">
                        <button class="del-btn"><i class="fa-solid fa-trash"></i></button>
                    </form>
                </div>
            </td>
        </tr>
        {% endfor %}
    </table>

    <script>
    function handleSave() {
        const user = document.getElementById('inUser').value;
        const pass = document.getElementById('inPass').value;
        const days = document.getElementById('inDays').value || "30";
        if(!user || !pass) return alert("ဖြည့်ပါ");

        document.getElementById('rUser').innerText = user;
        document.getElementById('rPass').innerText = pass;
        let d = new Date(); d.setDate(d.getDate() + parseInt(days));
        document.getElementById('rDate').innerText = d.toISOString().split('T')[0];

        html2canvas(document.getElementById('receipt')).then(canvas => {
            const link = document.createElement('a');
            link.download = 'KSO_'+user+'.png';
            link.href = canvas.toDataURL();
            link.click();
            setTimeout(() => { document.getElementById('userForm').submit(); }, 500);
        });
    }
    </script>
    {% endif %}
</div>
</body></html>
"""

def get_users():
    try:
        with open(USERS_FILE, "r") as f: data = json.load(f)
    except: data = []
    for u in data:
        exp = datetime.strptime(u['expires'], "%Y-%m-%d")
        u['days_left'] = (exp - datetime.now()).days
    return data

def sync_vpn():
    users = get_users()
    passwords = [u['password'] for u in users]
    try:
        with open(CONFIG_FILE, "r") as f: cfg = json.load(f)
        cfg['auth']['config'] = passwords
        with open(CONFIG_FILE, "w") as f: json.dump(cfg, f, indent=2)
        subprocess.run(["systemctl", "restart", "zivpn"])
    except: pass

@app.route("/")
def index():
    if not session.get('auth'): return render_template_string(HTML, authed=False, logo=LOGO_URL)
    return render_template_string(HTML, authed=True, logo=LOGO_URL, users=get_users())

@app.route("/login", methods=["POST"])
def login():
    u, p = request.form.get("u"), request.form.get("p")
    if u == os.environ.get("WEB_ADMIN_USER") and p == os.environ.get("WEB_ADMIN_PASSWORD"):
        session['auth'] = True
    return redirect("/")

@app.route("/logout")
def logout(): session.clear(); return redirect("/")

@app.route("/add", methods=["POST"])
def add():
    user, password = request.form.get("user"), request.form.get("password")
    expires_raw = request.form.get("expires")
    if expires_raw.isdigit():
        expires = (datetime.now() + timedelta(days=int(expires_raw))).strftime("%Y-%m-%d")
    else:
        expires = expires_raw # If date picker used

    data = get_users()
    found = False
    for u in data:
        if u['user'] == user:
            u['password'], u['expires'] = password, expires
            found = True; break
    if not found: data.append({"user": user, "password": password, "expires": expires})
    
    with open(USERS_FILE, "w") as f: json.dump(data, f)
    sync_vpn()
    return redirect("/")

@app.route("/delete", methods=["POST"])
def delete():
    user = request.form.get("user")
    data = [u for u in get_users() if u['user'] != user]
    with open(USERS_FILE, "w") as f: json.dump(data, f)
    sync_vpn()
    return redirect("/")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8880)
PY

# ===== Service Setup =====
cat >/etc/systemd/system/zivpn-web.service <<EOF
[Unit]
Description=ZIVPN Web Panel
After=network.target
[Service]
Type=simple
User=root
EnvironmentFile=$ENVF
ExecStart=/usr/bin/python3 /etc/zivpn/web.py
Restart=always
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now zivpn-web 2>/dev/null || systemctl restart zivpn-web

IP=$(hostname -I | awk '{print $1}')
echo -e "\n$LINE"
echo -e "${G}✅ အားလုံး အဆင်သင့်ဖြစ်ပါပြီ!${Z}"
echo -e "${C}Web Panel:${Z} ${Y}http://$IP:8880${Z}"
echo -e "$LINE"

