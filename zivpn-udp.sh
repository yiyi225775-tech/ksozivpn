#!/bin/bash
# ZIVPN UDP Server + Web UI (KSO Final - Custom Admin Login)
set -euo pipefail

# ===== Pretty =====
B="\e[1;34m"; G="\e[1;32m"; Y="\e[1;33m"; R="\e[1;31m"; C="\e[1;36m"; Z="\e[0m"
LINE="${B}────────────────────────────────────────────────────────${Z}"
say(){ echo -e "$1"; }

clear
echo -e "$LINE"
echo -e "${G}🌟 ZIVPN KSO Advanced Setup (Custom Admin)${Z}"
echo -e "$LINE"

# Root check
if [ "$(id -u)" -ne 0 ]; then echo -e "${R}Root user ဖြင့် run ပါ။${Z}"; exit 1; fi

# Get Custom Admin Credentials
read -p "Admin နာမည် ပေးပါ (ဥပမာ- kso): " ADMIN_U
read -p "စကားဝှက် ပေးပါ (ဥပမာ- 123456): " ADMIN_P

if [[ -z "$ADMIN_U" || -z "$ADMIN_P" ]]; then
    echo -e "${R}နာမည်နဲ့ စကားဝှက် မဖြစ်မနေ ထည့်ရပါမယ်။ နောက်မှ ပြန် run ပါ။${Z}"
    exit 1
fi

# Paths & Files
mkdir -p /etc/zivpn
ENVF="/etc/zivpn/web.env"

# Save Credentials to Env file
echo "WEB_ADMIN_USER=$ADMIN_U" > "$ENVF"
echo "WEB_ADMIN_PASSWORD=$ADMIN_P" >> "$ENVF"
echo "WEB_SECRET=$(openssl rand -hex 16)" >> "$ENVF"

# Install basics
say "${Y}📦 System လိုအပ်ချက်များ တင်နေသည်...${Z}"
apt-get update -y >/dev/null && apt-get install -y curl ufw jq python3 python3-flask iproute2 openssl >/dev/null

# Flask Web UI Script
cat > /etc/zivpn/web.py <<'PY'
import os, json, subprocess
from flask import Flask, render_template_string, request, redirect, url_for, session
from datetime import datetime

app = Flask(__name__)
app.secret_key = os.environ.get("WEB_SECRET", "secret")
ADMIN_USER = os.environ.get("WEB_ADMIN_USER")
ADMIN_PASS = os.environ.get("WEB_ADMIN_PASSWORD")

USERS_FILE = "/etc/zivpn/users.json"
CONFIG_FILE = "/etc/zivpn/config.json"
IP_ADDR = subprocess.check_output(["hostname", "-I"]).decode().split()[0]

def get_users():
    if not os.path.exists(USERS_FILE): return []
    try:
        with open(USERS_FILE, "r") as f: return json.load(f)
    except: return []

def save_users(users):
    with open(USERS_FILE, "w") as f: json.dump(users, f, indent=2)
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, "r") as f: cfg = json.load(f)
            cfg["auth"]["config"] = [u["password"] for u in users]
            with open(CONFIG_FILE, "w") as f: json.dump(cfg, f, indent=2)
            subprocess.run(["systemctl", "restart", "zivpn"])
        except: pass

HTML = """
<!DOCTYPE html>
<html lang="my">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>KSO ZIVPN PANEL</title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <style>
        body { font-family: 'Segoe UI', sans-serif; background: #f0f2f5; margin: 0; padding: 15px; }
        .container { max-width: 450px; margin: auto; }
        .header-box { background: #2563eb; color: white; padding: 20px; border-radius: 15px; text-align: center; margin-bottom: 15px; }
        .card { background: white; padding: 20px; border-radius: 15px; box-shadow: 0 4px 12px rgba(0,0,0,0.1); margin-bottom: 15px; }
        label { display: block; font-weight: bold; margin-bottom: 5px; font-size: 13px; color: #64748b; }
        input { width: 100%; padding: 10px; border: 1px solid #e2e8f0; border-radius: 8px; box-sizing: border-box; margin-bottom: 12px; }
        .btn-add { width: 100%; padding: 12px; background: #2563eb; color: white; border: none; border-radius: 8px; font-weight: bold; cursor: pointer; }
        .user-card { background: white; border-left: 5px solid #2563eb; padding: 15px; border-radius: 10px; margin-bottom: 10px; }
        .info-row { display: flex; justify-content: space-between; align-items: center; margin-bottom: 6px; font-size: 13px; }
        .copy-btn { background: #f1f5f9; border: 1px solid #cbd5e1; padding: 3px 7px; border-radius: 4px; cursor: pointer; font-size: 10px; }
        .actions { display: flex; gap: 8px; margin-top: 10px; }
        .btn-edit { background: #10b981; color: white; flex: 1.5; padding: 8px; border-radius: 6px; border:none; font-size: 12px; cursor:pointer; }
        .btn-del { background: #ef4444; color: white; flex: 1; padding: 8px; border-radius: 6px; border:none; font-size: 12px; cursor:pointer; }
        .badge { font-size: 11px; padding: 2px 8px; border-radius: 10px; background: #dcfce7; color: #166534; font-weight: bold; }
    </style>
</head>
<body>
    <div class="container">
        {% if not session.get("auth") %}
        <div class="card">
            <h2 style="text-align:center;">Admin Login</h2>
            <form method="post" action="/login">
                <label>Username</label><input type="text" name="u" required>
                <label>Password</label><input type="password" name="p" required>
                <button class="btn-add">Login</button>
            </form>
        </div>
        {% else %}
        <div class="header-box">
            <h2 style="margin:0;">KSO VIP PANEL</h2>
            <div style="margin-top:10px; background: rgba(255,255,255,0.2); display:inline-block; padding: 5px 15px; border-radius: 20px;">
                User စုစုပေါင်း: <b>{{ count }}</b> ယောက်
            </div>
        </div>

        <div class="card">
            <form method="post" action="/add" id="userForm">
                <div style="display:grid; grid-template-columns: 1fr 1fr; gap:10px;">
                    <div><label>User Name</label><input type="text" name="user" id="inUser" required></div>
                    <div><label>Password</label><input type="text" name="pass" id="inPass" required></div>
                </div>
                <div style="display:grid; grid-template-columns: 1fr 1fr; gap:10px;">
                    <div><label>Port (UDP)</label><input type="number" name="port" id="inPort" placeholder="6000" required></div>
                    <div><label>Expire Date</label><input type="date" name="exp" id="inExp" value="{{today}}" required></div>
                </div>
                <button class="btn-add">သိမ်းဆည်းမည် / သက်တမ်းတိုးမည်</button>
            </form>
        </div>

        {% for u in users %}
        <div class="user-card">
            <div class="info-row">
                <span style="font-weight:bold;"><i class="fa fa-user"></i> {{u.user}}</span>
                <span class="badge">{{ u.days_left }} ရက်ကျန်</span>
            </div>
            <div class="info-row"><span><b>IP:</b> {{ip}}</span> <button class="copy-btn" onclick="copy('{{ip}}')">Copy</button></div>
            <div class="info-row"><span><b>Pass:</b> {{u.password}}</span> <button class="copy-btn" onclick="copy('{{u.password}}')">Copy</button></div>
            <div class="info-row"><span><b>Expire:</b> {{u.expires}}</span> <button class="copy-btn" onclick="copy('{{u.expires}}')">Copy</button></div>
            
            <div class="actions">
                <button class="btn-edit" onclick="editUser('{{u.user}}', '{{u.password}}', '{{u.port}}', '{{u.expires}}')">သက်တမ်းတိုး</button>
                <form method="post" action="/delete" style="flex:1;"><input type="hidden" name="user" value="{{u.user}}"><button class="btn-del">ဖျက်ရန်</button></form>
            </div>
        </div>
        {% endfor %}
        <a href="/logout" style="display:block; text-align:center; margin-top:10px; color:#64748b; font-size:12px;">Logout</a>
        {% endif %}
    </div>
    <script>
        function copy(t) { navigator.clipboard.writeText(t); alert("Copied!"); }
        function editUser(n, p, po, d) {
            document.getElementById('inUser').value = n;
            document.getElementById('inPass').value = p;
            document.getElementById('inPort').value = po;
            document.getElementById('inExp').value = d;
            window.scrollTo({top:0, behavior:'smooth'});
        }
    </script>
</body>
</html>
"""

@app.route("/")
def index():
    raw_users = get_users()
    today_dt = datetime.now()
    processed_users = []
    for u in raw_users:
        try:
            exp_dt = datetime.strptime(u['expires'], "%Y-%m-%d")
            delta = (exp_dt - today_dt).days + 1
            u['days_left'] = delta if delta > 0 else 0
        except: u['days_left'] = 0
        processed_users.append(u)
    return render_template_string(HTML, users=processed_users, count=len(processed_users), ip=IP_ADDR, today=today_dt.strftime("%Y-%m-%d"))

@app.route("/login", methods=["POST"])
def login():
    if request.form.get("u") == ADMIN_USER and request.form.get("p") == ADMIN_PASS:
        session["auth"] = True
    return redirect("/")

@app.route("/logout")
def logout():
    session.clear()
    return redirect("/")

@app.route("/add", methods=["POST"])
def add():
    if not session.get("auth"): return redirect("/")
    users = get_users()
    name = request.form.get("user")
    users = [u for u in users if u["user"] != name]
    users.append({"user": name, "password": request.form.get("pass"), "port": request.form.get("port"), "expires": request.form.get("exp")})
    save_users(users)
    return redirect("/")

@app.route("/delete", methods=["POST"])
def delete():
    if not session.get("auth"): return redirect("/")
    user = request.form.get("user")
    users = [u for u in get_users() if u["user"] != user]
    save_users(users)
    return redirect("/")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8880)
PY

# Systemd Service setup
cat > /etc/systemd/system/zivpn-web.service <<EOF
[Unit]
Description=ZIVPN Web Panel
After=network.target
[Service]
EnvironmentFile=/etc/zivpn/web.env
ExecStart=/usr/bin/python3 /etc/zivpn/web.py
Restart=always
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now zivpn-web.service
systemctl restart zivpn-web.service

# Setup Networking
sysctl -w net.ipv4.ip_forward=1 >/dev/null
IFACE=$(ip -4 route ls | awk '/default/ {print $5; exit}')
iptables -t nat -F PREROUTING || true
iptables -t nat -A PREROUTING -i "$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667
iptables -t nat -A POSTROUTING -o "$IFACE" -j MASQUERADE
ufw allow 8880/tcp >/dev/null
ufw allow 6000:19999/udp >/dev/null

echo -e "$LINE"
say "${G}✅ အားလုံး အဆင်သင့်ဖြစ်ပါပြီ။${Z}"
say "${C}Login User:${Z} $ADMIN_U"
say "${C}Login Pass:${Z} $ADMIN_P"
say "${C}Panel Link:${Z} http://$(hostname -I | awk '{print $1}'):8880"
echo -e "$LINE"
