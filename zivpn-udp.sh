#!/bin/bash
# ZIVPN UDP Server + Web UI (Myanmar) - Professional Edition
# Fix: HTTP Clipboard Copy, Individual Copy Buttons, Status Colors

set -euo pipefail

# ===== Pretty Colors =====
B="\e[1;34m"; G="\e[1;32m"; Y="\e[1;33m"; R="\e[1;31m"; C="\e[1;36m"; M="\e[1;35m"; Z="\e[0m"
LINE="${B}────────────────────────────────────────────────────────${Z}"

say(){ echo -e "$1"; }

# Error ဖြစ်နေရင် အရင်ရှင်းမယ် (Text file busy fix)
systemctl stop zivpn zivpn-web 2>/dev/null || true
pkill zivpn 2>/dev/null || true

echo -e "\n$LINE\n${G}🌟 ZIVPN UDP-KSO (Expert Copy Mode) မှ ကြိုဆိုပါတယ်${Z}\n$LINE"

# ===== Root check =====
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${R}ဤ script ကို root အဖြစ် run ရပါမယ် (sudo -i)${Z}"; exit 1
fi

export DEBIAN_FRONTEND=noninteractive

# ===== Packages Installation =====
say "${Y}📦 လိုအပ်သော Packages များ ထည့်သွင်းနေသည်...${Z}"
apt-get update -y >/dev/null
apt-get install -y curl ufw jq python3 python3-flask python3-apt iproute2 conntrack ca-certificates openssl >/dev/null

# ===== Paths & Setup =====
BIN="/usr/local/bin/zivpn"
CFG="/etc/zivpn/config.json"
USERS="/etc/zivpn/users.json"
ENVF="/etc/zivpn/web.env"
mkdir -p /etc/zivpn

# Binary Download
curl -fsSL -o "$BIN" "https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64" || \
curl -fSL -o "$BIN" "https://github.com/zahidbd2/udp-zivpn/releases/latest/download/udp-zivpn-linux-amd64"
chmod +x "$BIN"

# SSL Certs
if [ ! -f /etc/zivpn/zivpn.crt ]; then
    openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
    -subj "/C=MM/ST=Yangon/L=Yangon/O=UPK/OU=Net/CN=zivpn" \
    -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt" >/dev/null 2>&1
fi

# Admin Login Setup
say "${Y}🔒 Web Admin အတွက် Username/Password သတ်မှတ်ပါ${Z}"
read -r -p "Admin Username (Default: admin): " WEB_USER
WEB_USER=${WEB_USER:-admin}
read -r -s -p "Admin Password (Default: admin123): " WEB_PASS; echo
WEB_PASS=${WEB_PASS:-admin123}
WEB_SECRET=$(openssl rand -hex 16)

echo "WEB_ADMIN_USER=${WEB_USER}" > "$ENVF"
echo "WEB_ADMIN_PASSWORD=${WEB_PASS}" >> "$ENVF"
echo "WEB_SECRET=${WEB_SECRET}" >> "$ENVF"
chmod 600 "$ENVF"

# Initial Config
[ -f "$USERS" ] || echo "[]" > "$USERS"
if [ ! -f "$CFG" ]; then
    echo '{"auth":{"mode":"passwords","config":["zi"]},"listen":":5667","cert":"/etc/zivpn/zivpn.crt","key":"/etc/zivpn/zivpn.key","obfs":"zivpn"}' > "$CFG"
fi

# ===== Web Python Script (With Fixed HTTP Copy) =====
cat > /etc/zivpn/web.py << 'PY'
import os, json, subprocess, hmac, re
from flask import Flask, render_template_string, request, redirect, url_for, session, jsonify
from datetime import datetime, timedelta

app = Flask(__name__)
app.secret_key = os.environ.get("WEB_SECRET", "dev-secret")
USERS_FILE = "/etc/zivpn/users.json"
CONFIG_FILE = "/etc/zivpn/config.json"

def get_vps_ip():
    try: return subprocess.check_output(["hostname", "-I"]).decode().split()[0]
    except: return "127.0.0.1"

VPS_IP = get_vps_ip()

def load_users():
    if not os.path.exists(USERS_FILE): return []
    try:
        with open(USERS_FILE, "r") as f:
            data = json.load(f)
            for u in data:
                try:
                    exp_date = datetime.strptime(u['expires'], "%Y-%m-%d")
                    u['days_left'] = (exp_date - datetime.now()).days
                except: u['days_left'] = 0
            return data
    except: return []

def save_users(data):
    with open(USERS_FILE, "w") as f: json.dump(data, f, indent=2)

def sync_vpn():
    users = load_users()
    pws = sorted(list(set([u["password"] for u in users])))
    try:
        with open(CONFIG_FILE, "r") as f: cfg = json.load(f)
        cfg["auth"]["config"] = pws if pws else ["zi"]
        with open(CONFIG_FILE, "w") as f: json.dump(cfg, f, indent=2)
        subprocess.run(["systemctl", "restart", "zivpn.service"])
    except: pass

HTML = """
<!DOCTYPE html>
<html lang="my">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <style>
        :root { --p:#2563eb; --bg:#f1f5f9; --card:#ffffff; --ok:#10b981; --warn:#f59e0b; --bad:#ef4444; }
        body { font-family: 'Segoe UI', sans-serif; background: var(--bg); margin:0; padding:15px; color:#334155; }
        .container { width:100%; max-width:650px; margin:auto; }
        .card { background:var(--card); padding:20px; border-radius:12px; box-shadow:0 4px 6px -1px rgba(0,0,0,0.1); margin-bottom:15px; }
        .btn { padding:10px; border:none; border-radius:8px; cursor:pointer; font-weight:bold; width:100%; margin-top:5px; }
        .btn-p { background:var(--p); color:white; }
        .status-pill { padding:3px 8px; border-radius:12px; font-size:10px; font-weight:bold; color:white; }
        .bg-ok { background:var(--ok); } .bg-warn { background:var(--warn); } .bg-bad { background:var(--bad); }
        table { width:100%; border-collapse:collapse; margin-top:10px; }
        th { text-align:left; font-size:11px; color:#64748b; padding:8px; border-bottom:2px solid #f1f5f9; }
        td { padding:10px 8px; border-bottom:1px solid #f1f5f9; font-size:13px; }
        .copy-btn { color:var(--p); cursor:pointer; margin-left:5px; font-size:12px; }
        .action-row { display:flex; gap:10px; }
        input { width:100%; padding:9px; border:1px solid #cbd5e1; border-radius:6px; box-sizing:border-box; }
        .toast { position:fixed; bottom:20px; right:20px; background:#1e293b; color:white; padding:10px 20px; border-radius:8px; display:none; z-index:99; }
    </style>
</head>
<body>
    <div id="toast" class="toast">Copied!</div>
    <div class="container">
        {% if not authed %}
            <div class="card" style="max-width:350px; margin:100px auto; text-align:center;">
                <h2 style="color:var(--p)">ADMIN LOGIN</h2>
                <form method="post" action="/login">
                    <input name="u" placeholder="Username" required style="margin-bottom:10px;">
                    <input name="p" type="password" placeholder="Password" required>
                    <button class="btn btn-p">LOGIN</button>
                </form>
            </div>
        {% else %}
            <div style="text-align:center; margin-bottom:15px;">
                <h2 style="margin:0; color:var(--p);">KSO VIP PANEL</h2>
                <span style="font-size:12px;">Server IP: <b>{{vps_ip}}</b> <i class="fa-regular fa-copy copy-btn" onclick="copyText('{{vps_ip}}')"></i></span>
            </div>

            <div class="card">
                <form method="post" action="/add">
                    <div style="display:grid; grid-template-columns:1fr 1fr; gap:10px;">
                        <input name="user" id="inUser" placeholder="အသုံးပြုသူအမည်" required>
                        <input name="password" id="inPass" placeholder="စကားဝှက်" required>
                    </div>
                    <div style="display:grid; grid-template-columns:1fr 1fr; gap:10px; margin-top:10px;">
                        <input name="days" id="inDays" placeholder="ရက်ပေါင်း (Default 30)">
                        <input name="port" placeholder="Port (Auto)" readonly>
                    </div>
                    <button class="btn btn-p">SAVE ACCOUNT</button>
                </form>
            </div>

            <div class="card" style="overflow-x:auto;">
                <table id="userTable">
                    <thead>
                        <tr>
                            <th>User/IP</th>
                            <th>Password</th>
                            <th>Expires</th>
                            <th>Action</th>
                        </tr>
                    </thead>
                    <tbody>
                        {% for u in users %}
                        <tr>
                            <td>
                                <b>{{u.user}}</b> <i class="fa-regular fa-copy copy-btn" onclick="copyText('{{u.user}}')"></i><br>
                                <small>{{vps_ip}}</small>
                            </td>
                            <td>
                                <code>{{u.password}}</code> <i class="fa-regular fa-copy copy-btn" onclick="copyText('{{u.password}}')"></i>
                            </td>
                            <td>
                                {% if u.days_left > 10 %}
                                    <span class="status-pill bg-ok">{{u.days_left}} d</span>
                                {% elif u.days_left > 3 %}
                                    <span class="status-pill bg-warn">{{u.days_left}} d</span>
                                {% else %}
                                    <span class="status-pill bg-bad">{{u.days_left}} d</span>
                                {% endif %}
                                <br><small>{{u.expires}}</small> <i class="fa-regular fa-copy copy-btn" onclick="copyText('{{u.expires}}')"></i>
                            </td>
                            <td>
                                <div class="action-row">
                                    <i class="fa-solid fa-pen-to-square" style="color:var(--p); cursor:pointer;" onclick="edit('{{u.user}}', '{{u.password}}')"></i>
                                    <i class="fa-solid fa-share-nodes" style="color:#64748b; cursor:pointer;" onclick="copyFull('{{vps_ip}}', '{{u.user}}', '{{u.password}}', '{{u.expires}}')"></i>
                                    <form method="post" action="/delete" style="display:inline;" onsubmit="return confirm('ဖျက်မှာလား?')">
                                        <input type="hidden" name="user" value="{{u.user}}">
                                        <button style="border:none; background:none; padding:0; cursor:pointer;"><i class="fa-solid fa-trash-can" style="color:var(--bad);"></i></button>
                                    </form>
                                </div>
                            </td>
                        </tr>
                        {% endfor %}
                    </tbody>
                </table>
            </div>
            <div style="text-align:center;"><a href="/logout" style="color:var(--bad); font-size:12px; text-decoration:none;">Logout Panel</a></div>
        {% endif %}
    </div>

    <script>
        // HTTP မှာပါ အလုပ်လုပ်တဲ့ Copy Function
        function copyText(txt) {
            const el = document.createElement('textarea');
            el.value = txt;
            document.body.appendChild(el);
            el.select();
            document.execCommand('copy');
            document.body.removeChild(el);
            showToast("Copied: " + txt);
        }

        function copyFull(ip, u, p, exp) {
            const full = `🌐 KSO VIP ACCOUNT\\n───────────────\\nIP: ${ip}\\nUser: ${u}\\nPass: ${p}\\nExpire: ${exp}\\n───────────────`;
            copyText(full);
        }

        function showToast(msg) {
            const t = document.getElementById('toast');
            t.innerText = msg;
            t.style.display = 'block';
            setTimeout(() => { t.style.display = 'none'; }, 2000);
        }

        function edit(u, p) {
            document.getElementById('inUser').value = u;
            document.getElementById('inPass').value = p;
            window.scrollTo({top: 0, behavior: 'smooth'});
        }
    </script>
</body>
</html>
"""

@app.route("/")
def index():
    if not session.get("authed"): return render_template_string(HTML, authed=False)
    return render_template_string(HTML, authed=True, users=load_users(), vps_ip=VPS_IP)

@app.route("/login", methods=["POST"])
def login():
    if request.form.get("u") == os.environ.get("WEB_ADMIN_USER") and \
       request.form.get("p") == os.environ.get("WEB_ADMIN_PASSWORD"):
        session["authed"] = True
    return redirect(url_for("index"))

@app.route("/logout")
def logout():
    session.clear(); return redirect(url_for("index"))

@app.route("/add", methods=["POST"])
def add_user():
    if not session.get("authed"): return redirect(url_for("index"))
    user, password = request.form.get("user").strip(), request.form.get("password").strip()
    days = int(request.form.get("days") or 30)
    expires = (datetime.now() + timedelta(days=days)).strftime("%Y-%m-%d")
    users = [u for u in load_users() if u["user"] != user]
    users.append({"user": user, "password": password, "expires": expires})
    save_users(users); sync_vpn()
    return redirect(url_for("index"))

@app.route("/delete", methods=["POST"])
def delete_user():
    if not session.get("authed"): return redirect(url_for("index"))
    user = request.form.get("user")
    users = [u for u in load_users() if u["user"] != user]
    save_users(users); sync_vpn()
    return redirect(url_for("index"))

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8880)
PY

# ===== Systemd Setup =====
cat >/etc/systemd/system/zivpn.service <<EOF
[Unit]
Description=ZIVPN UDP Server
After=network.target
[Service]
ExecStart=$BIN server -c $CFG
Restart=always
User=root
[Install]
WantedBy=multi-user.target
EOF

cat >/etc/systemd/system/zivpn-web.service <<EOF
[Unit]
Description=ZIVPN Web Panel
After=network.target
[Service]
EnvironmentFile=$ENVF
ExecStart=/usr/bin/python3 /etc/zivpn/web.py
Restart=always
[Install]
WantedBy=multi-user.target
EOF

# ===== Networking & Firewall =====
sysctl -w net.ipv4.ip_forward=1
IFACE=$(ip -4 route ls | awk '/default/ {print $5; exit}')
iptables -t nat -D PREROUTING -i "$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667 2>/dev/null || true
iptables -t nat -A PREROUTING -i "$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667
iptables -t nat -A POSTROUTING -o "$IFACE" -j MASQUERADE
ufw allow 5667/udp && ufw allow 6000:19999/udp && ufw allow 8880/tcp

# ===== Launch =====
systemctl daemon-reload
systemctl enable --now zivpn zivpn-web
systemctl restart zivpn zivpn-web

IP=$(hostname -I | awk '{print $1}')
echo -e "\n$LINE"
say "${G}✅ အကုန်လုံး ပေါင်းစည်းပြီးပါပြီ${Z}"
say "${C}Web Panel :${Z} ${Y}http://$IP:8880${Z}"
say "${C}Admin User:${Z} ${Y}$WEB_USER${Z}"
say "${C}Admin Pass:${Z} ${Y}$WEB_PASS${Z}"
echo -e "$LINE\n"

