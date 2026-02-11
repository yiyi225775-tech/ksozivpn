#!/bin/bash
# ZIVPN UDP Server + Web UI (KSO Modified)
# Features: Date Picker, Copy Buttons (User, Pass, IP, Date), and Detailed User Info.

set -euo pipefail

# ===== Pretty =====
B="\e[1;34m"; G="\e[1;32m"; Y="\e[1;33m"; R="\e[1;31m"; C="\e[1;36m"; Z="\e[0m"
LINE="${B}────────────────────────────────────────────────────────${Z}"
say(){ echo -e "$1"; }

echo -e "\n$LINE\n${G}🌟 ZIVPN UDP-KSO အဆင့်မြင့် Panel တင်နေသည်${Z}\n$LINE"

# Root check
if [ "$(id -u)" -ne 0 ]; then echo -e "${R}Root user ဖြင့် run ပါ။${Z}"; exit 1; fi

# Install dependencies
say "${Y}📦 လိုအပ်သော Packages များတင်နေသည်...${Z}"
apt-get update -y >/dev/null
apt-get install -y curl ufw jq python3 python3-flask python3-apt iproute2 conntrack openssl >/dev/null

# Paths
BIN="/usr/local/bin/zivpn"
CFG="/etc/zivpn/config.json"
USERS="/etc/zivpn/users.json"
ENVF="/etc/zivpn/web.env"
mkdir -p /etc/zivpn

# Download ZIVPN if not exists
if [ ! -f "$BIN" ]; then
    say "${Y}⬇️ ZIVPN Binary ဒေါင်းလုဒ်ဆွဲနေသည်...${Z}"
    curl -fsSL -o "$BIN" "https://github.com/zahidbd2/udp-zivpn/releases/latest/download/udp-zivpn-linux-amd64"
    chmod +x "$BIN"
fi

# Web Admin Settings
read -r -p "Web Admin Username (Enter=admin): " WEB_USER
WEB_USER=${WEB_USER:-admin}
read -r -s -p "Web Admin Password: " WEB_PASS
echo
WEB_SECRET=$(openssl rand -hex 16)

echo "WEB_ADMIN_USER=${WEB_USER}" > "$ENVF"
echo "WEB_ADMIN_PASSWORD=${WEB_PASS}" >> "$ENVF"
echo "WEB_SECRET=${WEB_SECRET}" >> "$ENVF"

# Flask Web UI Script
cat > /etc/zivpn/web.py <<'PY'
import os, json, subprocess, hmac, tempfile, re
from flask import Flask, render_template_string, request, redirect, url_for, session, jsonify
from datetime import datetime, timedelta

app = Flask(__name__)
app.secret_key = os.environ.get("WEB_SECRET", "secret")
ADMIN_USER = os.environ.get("WEB_ADMIN_USER", "admin")
ADMIN_PASS = os.environ.get("WEB_ADMIN_PASSWORD", "admin")

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
    sync_config(users)

def sync_config(users):
    if not os.path.exists(CONFIG_FILE): return
    with open(CONFIG_FILE, "r") as f: cfg = json.load(f)
    cfg["auth"]["config"] = [u["password"] for u in users]
    with open(CONFIG_FILE, "w") as f: json.dump(cfg, f, indent=2)
    subprocess.run(["systemctl", "restart", "zivpn"])

HTML = """
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>KSO ZIVPN PANEL</title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <style>
        body { font-family: sans-serif; background: #f4f6f9; padding: 20px; }
        .container { max-width: 500px; margin: auto; background: white; padding: 20px; border-radius: 15px; box-shadow: 0 4px 10px rgba(0,0,0,0.1); }
        .header { text-align: center; margin-bottom: 20px; }
        .input-group { margin-bottom: 15px; }
        label { display: block; font-weight: bold; margin-bottom: 5px; font-size: 14px; }
        input { width: 100%; padding: 10px; border: 1px solid #ddd; border-radius: 8px; box-sizing: border-box; }
        .btn { width: 100%; padding: 12px; border: none; border-radius: 8px; cursor: pointer; font-weight: bold; }
        .btn-add { background: #2563eb; color: white; }
        .user-card { background: #fff; border: 1px solid #eee; padding: 15px; border-radius: 10px; margin-top: 10px; position: relative; }
        .copy-btn { background: #eee; border: none; padding: 5px 10px; border-radius: 5px; cursor: pointer; font-size: 12px; margin-left: 5px; }
        .copy-btn:hover { background: #ddd; }
        .info-row { font-size: 14px; margin-bottom: 5px; display: flex; align-items: center; justify-content: space-between; }
        .status-online { color: green; font-weight: bold; }
        .btn-del { background: #ff4444; color: white; width: auto; padding: 5px 10px; font-size: 12px; margin-top: 10px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h2 style="color:#2563eb;">KSO VIP PANEL</h2>
            <p>Server IP: <b>{{ip}}</b> <button class="copy-btn" onclick="copyText('{{ip}}')">Copy IP</button></p>
        </div>

        {% if not session.get('auth') %}
        <form method="post" action="/login">
            <input type="text" name="u" placeholder="Username" required style="margin-bottom:10px;">
            <input type="password" name="p" placeholder="Password" required>
            <button class="btn btn-add" style="margin-top:15px;">LOGIN</button>
        </form>
        {% else %}
        <form method="post" action="/add">
            <div class="input-group">
                <label>User Name</label>
                <input type="text" name="user" required>
            </div>
            <div class="input-group">
                <label>Password</label>
                <input type="text" name="pass" required>
            </div>
            <div class="input-group">
                <label>Expire Date (ပြက္ခဒိန်)</label>
                <input type="date" name="exp" value="{{today}}" required>
            </div>
            <button class="btn btn-add">အကောင့်သစ်ဖွင့်မည်</button>
        </form>

        <hr>
        <h3>အသုံးပြုသူများ</h3>
        {% for u in users %}
        <div class="user-card">
            <div class="info-row"><span>User: <b>{{u.user}}</b></span> <button class="copy-btn" onclick="copyText('{{u.user}}')">Copy</button></div>
            <div class="info-row"><span>Pass: <b>{{u.password}}</b></span> <button class="copy-btn" onclick="copyText('{{u.password}}')">Copy</button></div>
            <div class="info-row"><span>Expire: {{u.expires}}</span> <button class="copy-btn" onclick="copyText('{{u.expires}}')">Copy</button></div>
            <form method="post" action="/delete" style="display:inline;">
                <input type="hidden" name="user" value="{{u.user}}">
                <button class="btn btn-del">ဖျက်ရန်</button>
            </form>
        </div>
        {% endfor %}
        <br><a href="/logout" style="text-align:center; display:block; color:red;">Logout</a>
        {% endif %}
    </div>

    <script>
        function copyText(text) {
            navigator.clipboard.writeText(text);
            alert("Copied: " + text);
        }
    </script>
</body>
</html>
"""

@app.route("/")
def index():
    users = get_users()
    today = datetime.now().strftime("%Y-%m-%d")
    return render_template_string(HTML, users=users, ip=IP_ADDR, today=today)

@app.route("/login", methods=["POST"])
def login():
    if request.form.get("u") == ADMIN_USER and request.form.get("p") == ADMIN_PASS:
        session["auth"] = True
    return redirect("/")

@app.route("/logout")
def logout():
    session.pop("auth", None)
    return redirect("/")

@app.route("/add", methods=["POST"])
def add():
    if not session.get("auth"): return redirect("/")
    users = get_users()
    users.append({
        "user": request.form.get("user"),
        "password": request.form.get("pass"),
        "expires": request.form.get("exp")
    })
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

# Create Systemd for Web
cat > /etc/systemd/system/zivpn-web.service <<EOF
[Unit]
Description=ZIVPN Web Management
After=network.target

[Service]
EnvironmentFile=/etc/zivpn/web.env
ExecStart=/usr/bin/python3 /etc/zivpn/web.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Networking
sysctl -w net.ipv4.ip_forward=1 >/dev/null
IFACE=$(ip -4 route ls | awk '/default/ {print $5; exit}')
iptables -t nat -A PREROUTING -i "$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667
iptables -t nat -A POSTROUTING -o "$IFACE" -j MASQUERADE
ufw allow 8880/tcp >/dev/null
ufw allow 5667/udp >/dev/null
ufw allow 6000:19999/udp >/dev/null

# Start services
systemctl daemon-reload
systemctl enable --now zivpn-web.service

IP=$(hostname -I | awk '{print $1}')
echo -e "$LINE"
say "${G}✅ အောင်မြင်စွာ တပ်ဆင်ပြီးပါပြီ။${Z}"
say "${C}Web UI Control Panel:${Z} ${Y}http://$IP:8880${Z}"
say "${C}Admin Username:${Z} ${WEB_USER}"
say "${C}Admin Password:${Z} ${WEB_PASS}"
echo -e "$LINE"

