#!/bin/bash
# ZIVPN UDP Server + Web UI (Myanmar)
# Features: Calendar for Creation, Expiry Edit, VPN IP display

set -euo pipefail

# ===== Colors =====
B="\e[1;34m"; G="\e[1;32m"; Y="\e[1;33m"; R="\e[1;31m"; C="\e[1;36m"; Z="\e[0m"
LINE="${B}────────────────────────────────────────────────────────${Z}"

say(){ echo -e "$1"; }

clear
echo -e "$LINE"
say "${G}   🌟 ZIVPN UDP-KSO (CALENDAR + IP DISPLAY) 🌟   "
say "${C}          Developed by KSO & Zahid Islam         "
echo -e "$LINE"

# ===== Root check =====
if [ "$(id -u)" -ne 0 ]; then
    say "${R}❌ ဤ script ကို root အဖြစ် run ရပါမယ် (sudo -i)${Z}"
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive

# ===== Packages =====
say "${Y}📦 Packages များ တင်နေပါတယ်။...${Z}"
apt-get update -y >/dev/null
apt-get install -y curl ufw jq python3 python3-flask python3-apt iproute2 conntrack ca-certificates openssl >/dev/null

# ===== Folders =====
mkdir -p /etc/zivpn
BIN="/usr/local/bin/zivpn"
CFG="/etc/zivpn/config.json"
USERS="/etc/zivpn/users.json"
ENVF="/etc/zivpn/web.env"
WEB_PY="/etc/zivpn/web.py"

# ===== Download Binary =====
say "${Y}⬇️ Binary ဒေါင်းလုဒ်ဆွဲနေပါတယ်...${Z}"
URL="https://github.com/zahidbd2/udp-zivpn/releases/latest/download/udp-zivpn-linux-amd64"
curl -fsSL -o "$BIN" "$URL"
chmod +x "$BIN"

# ===== SSL Certs =====
openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
    -subj "/C=MM/ST=Yangon/L=Yangon/O=KSO/OU=Net/CN=zivpn" \
    -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt" >/dev/null 2>&1

# ===== Web Login Setup =====
say "${G}🔑 Web Panel Login သတ်မှတ်ပါ${Z}"
read -r -p "Admin Username: " WEB_USER
read -r -s -p "Admin Password: " WEB_PASS; echo
WEB_SECRET=$(openssl rand -hex 16)
PUBLIC_IP=$(curl -s ifconfig.me)

echo "WEB_ADMIN_USER=${WEB_USER}" > "$ENVF"
echo "WEB_ADMIN_PASSWORD=${WEB_PASS}" >> "$ENVF"
echo "WEB_SECRET=${WEB_SECRET}" >> "$ENVF"
echo "VPN_PUBLIC_IP=${PUBLIC_IP}" >> "$ENVF"
chmod 600 "$ENVF"

if [ ! -f "$CFG" ]; then
    echo '{"listen":":5667","auth":{"mode":"passwords","config":["zi"]},"cert":"/etc/zivpn/zivpn.crt","key":"/etc/zivpn/zivpn.key","obfs":"zivpn"}' > "$CFG"
fi
[ -f "$USERS" ] || echo "[]" > "$USERS"

# ===== Python Web Panel =====
cat > "$WEB_PY" <<'PY'
import os, json, subprocess, hmac
from flask import Flask, render_template_string, request, redirect, session
from datetime import datetime, timedelta

app = Flask(__name__)
app.secret_key = os.environ.get("WEB_SECRET", "change-me")
ADMIN_USER = os.environ.get("WEB_ADMIN_USER", "admin")
ADMIN_PASS = os.environ.get("WEB_ADMIN_PASSWORD", "admin")
VPN_IP = os.environ.get("VPN_PUBLIC_IP", "0.0.0.0")

USERS_FILE = "/etc/zivpn/users.json"
CONFIG_FILE = "/etc/zivpn/config.json"
LOGO_URL = "https://raw.githubusercontent.com/KYAWSOEOO8/kso-script/main/icon.png"

def load_users():
    try:
        with open(USERS_FILE, "r") as f: return json.load(f)
    except: return []

def save_users(users):
    with open(USERS_FILE, "w") as f: json.dump(users, f, indent=2)

def sync_config():
    users = load_users()
    pws = [u["password"] for u in users]
    try:
        with open(CONFIG_FILE, "r") as f: cfg = json.load(f)
        cfg["auth"]["config"] = pws if pws else ["zi"]
        with open(CONFIG_FILE, "w") as f: json.dump(cfg, f, indent=2)
        subprocess.run(["systemctl", "restart", "zivpn"], check=False)
    except: pass

HTML = """
<!doctype html>
<html lang="my">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <title>KSO VIP PANEL</title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <script src="https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js"></script>
    <style>
        :root { --p: #2563eb; --bg: #f1f5f9; --card: #ffffff; --bad: #ef4444; }
        body { font-family: 'Segoe UI', sans-serif; background: var(--bg); margin:0; padding:15px; }
        .card { background: var(--card); padding: 20px; border-radius: 20px; box-shadow: 0 4px 6px -1px rgba(0,0,0,0.1); max-width: 450px; margin: auto; }
        .btn { background: var(--p); color: #fff; border: none; padding: 12px; border-radius: 10px; width: 100%; cursor: pointer; font-weight: bold; }
        input { width: 100%; padding: 10px; margin: 8px 0; border: 1px solid #ddd; border-radius: 8px; box-sizing: border-box; }
        .user-item { border: 1px solid #eee; padding: 12px; border-radius: 12px; margin-top: 10px; background: #fff; }
        .user-header { display: flex; justify-content: space-between; align-items: center; }
        .actions { display: flex; gap: 10px; }
        .cal-btn { color: var(--p); cursor: pointer; position: relative; font-size: 1.2em; }
        .cal-btn input { position: absolute; opacity: 0; left:0; top:0; width:100%; height:100%; cursor:pointer; }
        .ip-box { font-size: 0.8em; background: #e2e8f0; padding: 4px 8px; border-radius: 6px; color: #475569; display: inline-block; margin-top: 5px; cursor: pointer; }
        #receipt { background: #fff; padding: 30px; text-align: center; border: 3px dashed var(--p); width: 350px; position: fixed; left: -9999px; border-radius: 20px; }
    </style>
</head>
<body>
    <div class="card">
        {% if not session.get('auth') %}
            <h2 align="center">LOGIN</h2>
            <form method="post" action="/login">
                <input name="u" placeholder="Username" required>
                <input name="p" type="password" placeholder="Password" required>
                <button class="btn">Login</button>
            </form>
        {% else %}
            <div align="center">
                <img src="{{ logo }}" width="65" style="border-radius:15px; margin-bottom:5px;">
                <h2 style="margin:0; color:var(--p);">KSO VIP UDP</h2>
                <small>Server IP: <b>{{ vpn_ip }}</b></small>
            </div>
            <hr style="border:0.5px solid #eee; margin:15px 0;">
            
            <form method="post" action="/add" id="uForm">
                <label><small>အသုံးပြုသူအမည်</small></label>
                <input name="user" id="inUser" placeholder="Username" required>
                <label><small>စကားဝှက်</small></label>
                <input name="pass" id="inPass" placeholder="Password" required>
                <label><small>သက်တမ်းကုန်ဆုံးမည့်ရက်</small></label>
                <input type="date" name="expiry_date" id="inDate" required>
                <button type="button" class="btn" onclick="genReceipt()">CREATE & DOWNLOAD</button>
            </form>

            <h3 style="margin-top:20px;">Users List</h3>
            {% for u in users %}
                <div class="user-item">
                    <div class="user-header">
                        <div>
                            <strong>{{ u.user }}</strong><br>
                            <small style="color:gray;"><i class="fa-regular fa-calendar"></i> {{ u.expires }}</small>
                        </div>
                        <div class="actions">
                            <form method="post" action="/update_expiry" style="margin:0;" class="cal-btn">
                                <i class="fa-solid fa-calendar-day"></i>
                                <input type="hidden" name="user" value="{{ u.user }}">
                                <input type="date" name="new_date" onchange="this.form.submit()">
                            </form>
                            <form method="post" action="/delete" style="margin:0;" onsubmit="return confirm('ဖျက်မှာလား?')">
                                <input type="hidden" name="user" value="{{ u.user }}">
                                <button type="submit" style="color:var(--bad); border:none; background:none; cursor:pointer; font-size:1.1em;"><i class="fa-solid fa-trash"></i></button>
                            </form>
                        </div>
                    </div>
                    <div class="ip-box" onclick="copyIP('{{ vpn_ip }}')">
                        <i class="fa-solid fa-network-wired"></i> IP: {{ vpn_ip }} <small>(Copy)</small>
                    </div>
                </div>
            {% endfor %}
            <br><p align="center"><a href="/logout" style="color:gray; text-decoration:none; font-size:0.9em;">Logout</a></p>
        {% endif %}
    </div>

    <div id="receipt">
        <h1 style="color:var(--p); margin-bottom:5px;">KSO VIP UDP</h1>
        <hr>
        <div style="text-align:left; padding:10px 20px;">
            <p><b>Server IP:</b> {{ vpn_ip }}</p>
            <p><b>အသုံးပြုသူ:</b> <span id="rUser"></span></p>
            <p><b>စကားဝှက်:</b> <span id="rPass"></span></p>
            <p><b>ကုန်ဆုံးရက်:</b> <span id="rDate"></span></p>
        </div>
        <hr>
        <p><b>Premium UDP Service</b></p>
    </div>

    <script>
    function copyIP(ip) {
        navigator.clipboard.writeText(ip);
        alert("Copied IP: " + ip);
    }
    
    function genReceipt() {
        const u = document.getElementById('inUser').value;
        const p = document.getElementById('inPass').value;
        const d = document.getElementById('inDate').value;
        if(!u || !p || !d) return alert("အကုန်ဖြည့်ပါ");

        document.getElementById('rUser').innerText = u;
        document.getElementById('rPass').innerText = p;
        document.getElementById('rDate').innerText = d;

        html2canvas(document.getElementById('receipt'), {scale: 2}).then(canvas => {
            let link = document.createElement('a');
            link.download = 'KSO_'+u+'.png';
            link.href = canvas.toDataURL();
            link.click();
            document.getElementById('uForm').submit();
        });
    }
    </script>
</body>
</html>
"""

@app.route("/")
def index():
    users = load_users()
    return render_template_string(HTML, users=users, logo=LOGO_URL, vpn_ip=VPN_IP)

@app.route("/login", methods=["POST"])
def login():
    if request.form['u'] == ADMIN_USER and request.form['p'] == ADMIN_PASS:
        session['auth'] = True
    return redirect("/")

@app.route("/logout")
def logout():
    session.pop('auth', None)
    return redirect("/")

@app.route("/add", methods=["POST"])
def add():
    if not session.get('auth'): return redirect("/")
    users = load_users()
    user, pw, expiry = request.form['user'], request.form['pass'], request.form['expiry_date']
    users.append({"user": user, "password": pw, "expires": expiry})
    save_users(users)
    sync_config()
    return redirect("/")

@app.route("/update_expiry", methods=["POST"])
def update_expiry():
    if not session.get('auth'): return redirect("/")
    users = load_users()
    user_name, new_date = request.form['user'], request.form['new_date']
    for u in users:
        if u['user'] == user_name:
            u['expires'] = new_date
            break
    save_users(users)
    return redirect("/")

@app.route("/delete", methods=["POST"])
def delete():
    if not session.get('auth'): return redirect("/")
    users = [u for u in load_users() if u['user'] != request.form['user']]
    save_users(users)
    sync_config()
    return redirect("/")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8880)
PY

# ===== Services Setup =====
cat >/etc/systemd/system/zivpn.service <<EOF
[Unit]
Description=ZIVPN UDP Server
After=network.target
[Service]
WorkingDirectory=/etc/zivpn
ExecStart=$BIN server -c $CFG
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF

cat >/etc/systemd/system/zivpn-web.service <<EOF
[Unit]
Description=ZIVPN Web Panel
After=network.target
[Service]
EnvironmentFile=$ENVF
ExecStart=/usr/bin/python3 $WEB_PY
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF

# ===== Network & Firewall =====
sysctl -w net.ipv4.ip_forward=1 >/dev/null
IFACE=$(ip -4 route ls | awk '/default/ {print $5; exit}')
iptables -t nat -A PREROUTING -i "$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667
iptables -t nat -A POSTROUTING -o "$IFACE" -j MASQUERADE
ufw allow 5667/udp >/dev/null 2>&1
ufw allow 6000:19999/udp >/dev/null 2>&1
ufw allow 8880/tcp >/dev/null 2>&1

systemctl daemon-reload
systemctl enable --now zivpn zivpn-web 2>/dev/null || true

echo -e "$LINE"
say "${G}✅ အားလုံးပြီးစီးပါပြီ။ ပြက္ခဒိန် နှင့် IP Display ထည့်သွင်းပြီးပါပြီ။${Z}"
say "${C}Web Panel:${Z} ${Y}http://$PUBLIC_IP:8880${Z}"
echo -e "$LINE"
