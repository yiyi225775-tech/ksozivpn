#!/bin/bash
# ZIVPN UDP Server + Web UI (KSO Final Verified - Fixed Sync)
set -euo pipefail

# ===== Styles =====
B="\e[1;34m"; G="\e[1;32m"; Y="\e[1;33m"; R="\e[1;31m"; C="\e[1;36m"; Z="\e[0m"
LINE="${B}────────────────────────────────────────────────────────${Z}"

clear
echo -e "$LINE"
echo -e "${G}🌟 ZIVPN KSO FINAL VERIFIED SCRIPT (ZIVPN FIXED)${Z}"
echo -e "$LINE"

# 1. Root Check
if [ "$(id -u)" -ne 0 ]; then echo -e "${R}Root user ဖြင့် run ပါ။${Z}"; exit 1; fi

# Get Custom Login from User
read -p "Admin Username ပေးပါ: " ADMIN_U
read -p "Admin Password ပေးပါ: " ADMIN_P
if [[ -z "$ADMIN_U" || -z "$ADMIN_P" ]]; then echo -e "${R}Username/Password လိုအပ်ပါသည်။${Z}"; exit 1; fi

# 2. Environments & Files
mkdir -p /etc/zivpn
echo "WEB_ADMIN_USER=$ADMIN_U" > /etc/zivpn/web.env
echo "WEB_ADMIN_PASSWORD=$ADMIN_P" >> /etc/zivpn/web.env
echo "WEB_SECRET=$(openssl rand -hex 16)" >> /etc/zivpn/web.env

# Install Necessary Tools
apt-get update -y >/dev/null
apt-get install -y python3 python3-flask jq ufw iproute2 openssl >/dev/null

# 3. Python Web UI Script
cat > /etc/zivpn/web.py <<'PY'
import os, json, subprocess
from flask import Flask, render_template_string, request, redirect, session
from datetime import datetime

app = Flask(__name__)
app.secret_key = os.environ.get("WEB_SECRET")
ADMIN_USER = os.environ.get("WEB_ADMIN_USER")
ADMIN_PASS = os.environ.get("WEB_ADMIN_PASSWORD")

USERS_FILE = "/etc/zivpn/users.json"
CONFIG_FILE = "/etc/zivpn/config.json"

def get_ip():
    try: return subprocess.check_output(["hostname", "-I"]).decode().split()[0]
    except: return "127.0.0.1"

def load_data():
    if not os.path.exists(USERS_FILE): return []
    try:
        with open(USERS_FILE, "r") as f: return json.load(f)
    except: return []

def save_and_sync(users):
    # Save to users.json
    with open(USERS_FILE, "w") as f: json.dump(users, f, indent=2)
    
    # Sync with ZIVPN config.json
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, "r") as f: 
                cfg = json.load(f)
            
            # auth config ထဲကို password string list ပဲ ထည့်ပေးရမှာပါ
            cfg["auth"]["config"] = [str(u["password"]) for u in users]
            
            with open(CONFIG_FILE, "w") as f: 
                json.dump(cfg, f, indent=2)
            
            # Restart ZIVPN to apply changes
            subprocess.run(["systemctl", "restart", "zivpn"])
        except Exception as e:
            print(f"Sync Error: {e}")

HTML = """
<!DOCTYPE html>
<html lang="my">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>KSO ZIVPN CONTROL</title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <style>
        body { font-family: sans-serif; background: #f4f6f9; padding: 15px; margin: 0; }
        .container { max-width: 450px; margin: auto; }
        .header { background: #2563eb; color: white; padding: 20px; border-radius: 15px; text-align: center; margin-bottom: 20px; }
        .card { background: white; padding: 20px; border-radius: 15px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); margin-bottom: 20px; }
        label { display: block; font-size: 12px; font-weight: bold; color: #666; margin-bottom: 5px; }
        input { width: 100%; padding: 10px; border: 1px solid #ddd; border-radius: 8px; margin-bottom: 15px; box-sizing: border-box; }
        .btn-save { width: 100%; padding: 12px; background: #2563eb; color: white; border: none; border-radius: 8px; font-weight: bold; cursor: pointer; }
        .user-card { background: white; border-radius: 12px; padding: 15px; margin-bottom: 10px; border-left: 5px solid #2563eb; box-shadow: 0 2px 5px rgba(0,0,0,0.05); }
        .row { display: flex; justify-content: space-between; margin-bottom: 8px; font-size: 14px; }
        .copy { color: #2563eb; cursor: pointer; font-size: 12px; border: 1px solid #2563eb; padding: 2px 5px; border-radius: 4px; }
        .actions { display: flex; gap: 10px; margin-top: 10px; border-top: 1px solid #eee; padding-top: 10px; }
        .btn-edit { flex: 1; background: #10b981; color: white; border: none; padding: 8px; border-radius: 6px; cursor: pointer; }
        .btn-del { flex: 1; background: #ef4444; color: white; border: none; padding: 8px; border-radius: 6px; cursor: pointer; }
        .badge { background: #e0e7ff; color: #4338ca; padding: 2px 8px; border-radius: 10px; font-size: 11px; }
    </style>
</head>
<body>
    <div class="container">
        {% if not session.get('auth') %}
        <div class="card">
            <h2 style="text-align:center">Login</h2>
            <form method="post" action="/login">
                <input type="text" name="u" placeholder="Username" required>
                <input type="password" name="p" placeholder="Password" required>
                <button class="btn-save">Login</button>
            </form>
        </div>
        {% else %}
        <div class="header">
            <h2 style="margin:0">KSO VIP PANEL</h2>
            <p style="margin:5px 0 0; opacity:0.8">Total Users: {{ count }}</p>
        </div>

        <div class="card">
            <form method="post" action="/add">
                <div style="display:flex; gap:10px">
                    <div style="flex:1"><label>Username</label><input type="text" name="user" id="fUser" required></div>
                    <div style="flex:1"><label>Password</label><input type="text" name="pass" id="fPass" required></div>
                </div>
                <div style="display:flex; gap:10px">
                    <div style="flex:1"><label>UDP Port</label><input type="number" name="port" id="fPort" value="5667" required></div>
                    <div style="flex:1"><label>Expire Date</label><input type="date" name="exp" id="fExp" required></div>
                </div>
                <button class="btn-save">သိမ်းဆည်းမည် / သက်တမ်းတိုးမည်</button>
            </form>
        </div>

        {% for u in users %}
        <div class="user-card">
            <div class="row"><span style="font-weight:bold">{{ u.user }}</span> <span class="badge">{{ u.days }} Days Left</span></div>
            <div class="row"><span>IP: {{ ip }}</span> <span class="copy" onclick="cp('{{ip}}')">Copy</span></div>
            <div class="row"><span>Pass: {{ u.password }}</span> <span class="copy" onclick="cp('{{u.password}}')">Copy</span></div>
            <div class="row"><span>Port: {{ u.port }}</span> <span class="copy" onclick="cp('{{u.port}}')">Copy</span></div>
            
            <div class="actions">
                <button class="btn-edit" onclick="ed('{{u.user}}','{{u.password}}','{{u.port}}','{{u.expires}}')">သက်တမ်းတိုး</button>
                <form method="post" action="/del" style="flex:1"><input type="hidden" name="user" value="{{u.user}}"><button class="btn-del" onclick="return confirm('ဖျက်မှာလား?')">ဖျက်မည်</button></form>
            </div>
        </div>
        {% endfor %}
        <center><a href="/logout" style="color:red; text-decoration:none; font-size:13px">Logout</a></center>
        {% endif %}
    </div>
    <script>
        function cp(t){ navigator.clipboard.writeText(t); alert("Copied!"); }
        function ed(u,p,pt,e){
            document.getElementById('fUser').value=u;
            document.getElementById('fPass').value=p;
            document.getElementById('fPort').value=pt;
            document.getElementById('fExp').value=e;
            window.scrollTo({top:0, behavior:'smooth'});
        }
    </script>
</body>
</html>
"""

@app.route("/")
def index():
    users = load_data()
    now = datetime.now()
    for u in users:
        try:
            diff = (datetime.strptime(u['expires'], "%Y-%m-%d") - now).days + 1
            u['days'] = diff if diff > 0 else 0
        except: u['days'] = 0
    return render_template_string(HTML, users=users, count=len(users), ip=get_ip())

@app.route("/login", methods=["POST"])
def login():
    if request.form.get("u") == ADMIN_USER and request.form.get("p") == ADMIN_PASS:
        session['auth'] = True
    return redirect("/")

@app.route("/logout")
def logout(): session.clear(); return redirect("/")

@app.route("/add", methods=["POST"])
def add():
    if not session.get('auth'): return redirect("/")
    users = [u for u in load_data() if u['user'] != request.form.get("user")]
    users.append({
        "user": request.form.get("user"), 
        "password": request.form.get("pass"), 
        "port": request.form.get("port"), 
        "expires": request.form.get("exp")
    })
    save_and_sync(users)
    return redirect("/")

@app.route("/del", methods=["POST"])
def delete():
    if not session.get('auth'): return redirect("/")
    users = [u for u in load_data() if u['user'] != request.form.get("user")]
    save_and_sync(users)
    return redirect("/")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8880)
PY

# 4. Networking (ZIVPN Default Port)
sysctl -w net.ipv4.ip_forward=1 >/dev/null
IFACE=$(ip -4 route ls | awk '/default/ {print $5; exit}')
# Clean old rules
iptables -t nat -F PREROUTING || true
# Forwarding for UDP (Default Zivpn 5667)
iptables -t nat -A PREROUTING -i "$IFACE" -p udp --dport 5667 -j DNAT --to-destination :5667
iptables -t nat -A POSTROUTING -o "$IFACE" -j MASQUERADE
ufw allow 8880/tcp >/dev/null
ufw allow 5667/udp >/dev/null

# 5. Service Auto Start
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

systemctl daemon-reload
systemctl enable --now zivpn-web.service
systemctl restart zivpn-web.service

echo -e "$LINE"
echo -e "${G}✅ ZIVPN Fixed & UI Restored!${Z}"
echo -e "${C}URL:${Z} http://$(hostname -I | awk '{print $1}'):8880"
echo -e "$LINE"
