#!/bin/bash
# ZIVPN UDP Server + Web UI (Myanmar) - KSO Fixed Edition + IP Everywhere
set -euo pipefail

# ===== Colors =====
B="e[1;34m"; G="e[1;32m"; Y="e[1;33m"; R="e[1;31m"; C="e[1;36m"; Z="e[0m"
LINE="${B}────────────────────────────────────────────────────────${Z}"

echo -e "
$LINE
${G}🌟 ZIVPN UDP-KSO Fixed Web Panel Enhanced${Z}
$LINE"

# Root check
if [ "$(id -u)" -ne 0 ]; then echo -e "${R}Root user ဖြင့် run ပါ${Z}"; exit 1; fi

# Basic Installs
apt-get update -y && apt-get install -y curl ufw jq python3 python3-flask iproute2 conntrack openssl

# Paths
mkdir -p /etc/zivpn
BIN="/usr/local/bin/zivpn"
CFG="/etc/zivpn/config.json"
USERS="/etc/zivpn/users.json"
ENVF="/etc/zivpn/web.env"

# Download Binary
if [ ! -f "$BIN" ]; then
  curl -fsSL -o "$BIN" "https://github.com/zahidbd2/udp-zivpn/releases/latest/download/udp-zivpn-linux-amd64"
  chmod +x "$BIN"
fi

# Config & Certs
[ -f "$CFG" ] || echo '{"listen":":5667","auth":{"mode":"passwords","config":["zi"]},"obfs":"zivpn"}' > "$CFG"
[ -f "$USERS" ] || echo "[]" > "$USERS"
if [ ! -f /etc/zivpn/zivpn.crt ]; then
  openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 -subj "/CN=zivpn" -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt" >/dev/null 2>&1
fi

# Web Admin Credentials Setup
echo -e "${Y}Setup Web Login${Z}"
read -r -p "Username (Panel ထဲဝင်ဖို့): " WEB_USER
read -r -s -p "Password (Panel ထဲဝင်ဖို့): " WEB_PASS; echo
WEB_SECRET=$(openssl rand -hex 16)

# Save to env file clearly
cat > "$ENVF" << ENVE
WEB_ADMIN_USER=$WEB_USER
WEB_ADMIN_PASSWORD=$WEB_PASS
WEB_SECRET=$WEB_SECRET
ENVE
chmod 600 "$ENVF"

# ===== Enhanced Web UI - IP EVERYWHERE =====
cat > /etc/zivpn/web.py << 'PY'
import os, json, subprocess, hmac
from flask import Flask, render_template_string, request, redirect, session, jsonify
from datetime import datetime, timedelta

app = Flask(__name__)
app.secret_key = os.environ.get("WEB_SECRET", "kso-key")
USERS_FILE = "/etc/zivpn/users.json"
CONFIG_FILE = "/etc/zivpn/config.json"

def load_data():
    try:
        with open(USERS_FILE, "r") as f: return json.load(f)
    except: return []

def save_data(data):
    with open(USERS_FILE, "w") as f: json.dump(data, f, indent=2)
    try:
        with open(CONFIG_FILE, "r") as f: cfg = json.load(f)
        cfg["auth"]["config"] = [u["password"] for u in data if "password" in u]
        with open(CONFIG_FILE, "w") as f: json.dump(cfg, f, indent=2)
        subprocess.run(["systemctl", "restart", "zivpn"], check=False)
    except: pass

HTML = """
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>KSO VIP PANEL</title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <style>
        :root { --p: #2563eb; --bg: #f8fafc; --card: #ffffff; }
        body { font-family: sans-serif; background: var(--bg); margin: 0; padding: 20px; display: flex; flex-direction: column; align-items: center; }
        .container { width: 100%; max-width: 500px; }
        .card { background: var(--card); padding: 20px; border-radius: 15px; box-shadow: 0 4px 6px -1px rgba(0,0,0,0.1); margin-bottom: 20px; }
        .input-group { margin-bottom: 15px; }
        label { display: block; font-size: 12px; font-weight: bold; color: #64748b; margin-bottom: 5px; }
        input { width: 100%; padding: 10px; border: 1px solid #e2e8f0; border-radius: 8px; box-sizing: border-box; }
        .btn { cursor: pointer; border: none; padding: 10px 15px; border-radius: 8px; font-weight: bold; }
        .btn-add { background: var(--p); color: white; width: 100%; }
        .btn-exp { background: #f1f5f9; color: #475569; font-size: 11px; margin-right: 5px; }
        .user-row { background: white; border-radius: 12px; margin-bottom: 10px; border-left: 5px solid #ccc; padding: 15px; }
        .status-green { border-left-color: #10b981; }
        .status-yellow { border-left-color: #f59e0b; }
        .status-red { border-left-color: #ef4444; }
        .user-details { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; margin-bottom: 10px; font-size: 13px; }
        .detail-label { font-weight: bold; color: #64748b; }
        .detail-value { color: #1e293b; }
        .config-box { background: #1e293b; color: #38bdf8; padding: 12px; border-radius: 8px; font-family: monospace; font-size: 12px; cursor: pointer; margin-bottom: 15px; text-align: center; transition: background 0.3s; }
        .config-box:hover { background: #334155; }
        .actions { display: flex; gap: 8px; justify-content: flex-end; }
        .copy-icon { margin-left: 5px; }
        h2 { text-align: center; color: var(--p); margin-bottom: 10px; }
        .header-ip { background: #059669; color: white; padding: 15px; border-radius: 12px; text-align: center; margin-bottom: 20px; font-size: 18px; font-weight: bold; cursor: pointer; }
        .header-ip:hover { background: #047857; }
        .login-card::before { content: "Server IP: {{ip}}"; display: block; background: #1e293b; color: #38bdf8; padding: 10px; border-radius: 8px; text-align: center; font-family: monospace; margin-bottom: 15px; cursor: pointer; }
    </style>
</head>
<body>
    <div class="container">
        <h2>KSO VIP PANEL</h2>
        
        {% if not authed %}
        <div class="card login-card">
            <h3 style="text-align:center;">Login</h3>
            <form method="POST" action="/login">
                <div class="input-group"><label>Username</label><input name="u" required autofocus></div>
                <div class="input-group"><label>Password</label><input name="p" type="password" required></div>
                <button class="btn btn-add">အကောင့်ဝင်ရန်</button>
            </form>
        </div>
        {% else %}
        <div class="header-ip" onclick="copyText(this, '{{ip}}')">
            Server IP: {{ip}} <i class="fas fa-copy copy-icon" style="font-size:14px;"></i>
        </div>
        
        <div class="card">
            <form method="POST" action="/add" id="addForm">
                <div class="input-group"><label>Username</label><input name="user" id="uname" required></div>
                <div class="input-group"><label>Password</label><input name="password" id="upass" required></div>
                <div class="input-group"><label>ရက်ပေါင်း</label><input name="days" id="udays" value="30" type="number" min="1">
                <div style="margin-top:8px;">
                    <button type="button" class="btn btn-exp" onclick="setDays(30)">30 ရက် (1 လ)</button>
                    <button type="button" class="btn btn-exp" onclick="setDays(60)">60 ရက် (2 လ)</button>
                </div></div>
                <button class="btn btn-add">သိမ်းဆည်းမည်</button>
            </form>
        </div>
        {% endif %}
        
        {% for u in users %}
        <div class="user-row {% if u.days_left > 10 %}status-green{% elif u.days_left > 3 %}status-yellow{% else %}status-red{% endif %}">
            <div class="user-details">
                <div><span class="detail-label">Server IP:</span> <span class="detail-value">{{ip}}</span></div>
                <div><span class="detail-label">နာမည်:</span> <span class="detail-value">{{u.user}}</span></div>
                <div><span class="detail-label">စကားဝှက်:</span> <span class="detail-value">{{u.password}}</span></div>
                <div><span class="detail-label">ကုန်ရက်:</span> <span class="detail-value">{{u.expires}}</span></div>
                <div style="grid-column: span 2;"><span class="detail-label">ကျန်ရက်:</span> <span class="detail-value">{{u.days_left}} ရက်</span></div>
            </div>
            <div style="display: flex; gap: 10px; align-items: center;">
                <div class="config-box" style="font-size:11px;padding:8px;width:auto;" onclick="copyConfig('{{ip}}', '{{u.user}}', '{{u.password}}')">
                    Full Config <i class="fas fa-copy copy-icon"></i>
                </div>
                <div class="actions">
                    <button class="btn" style="background:#dcfce7; color:#166534; padding:8px 12px;" onclick="editUser('{{u.user}}','{{u.password}}')"><i class="fa-solid fa-edit"></i></button>
                    <form method="POST" action="/delete" style="display:inline;"><input type="hidden" name="user" value="{{u.user}}"><button class="btn" style="background:#fee2e2; color:#991b1b; padding:8px 12px;" type="submit"><i class="fa-solid fa-trash"></i></button></form>
                </div>
            </div>
        </div>
        {% endfor %}
        
        <a href="/logout" style="display:block; text-align:center; color:#ef4444; text-decoration:none; margin-top:20px;">Logout</a>
    </div>
    <script>
        function setDays(d) { document.getElementById('udays').value = d; }
        function editUser(u, p) { document.getElementById('uname').value = u; document.getElementById('upass').value = p; window.scrollTo(0,0); }
        function copyText(el, text) {
            navigator.clipboard.writeText(text).then(() => {
                el.style.background = "#047857";
                setTimeout(() => el.style.background = "#059669", 1000);
            });
        }
        function copyConfig(ip, user, pass) {
            const config = `Server IP: ${ip}
Username: ${user}
Password: ${pass}`;
            navigator.clipboard.writeText(config).then(() => {
                alert('✅ Full Config Copied!
IP + User + Pass အကုန်လုံး Copy လုပ်ပြီး');
            });
        }
    </script>
</body>
</html>
"""

@app.route("/")
def index():
    ip = request.host.split(":")[0]
    if not session.get("auth"):
        return render_template_string(HTML, authed=False, ip=ip, users=[])
    users = load_data()
    now = datetime.now()
    for u in users:
        try:
            exp = datetime.strptime(u["expires"], "%Y-%m-%d")
            u["days_left"] = max(0, (exp - now).days + 1)
        except: u["days_left"] = 0
    return render_template_string(HTML, authed=True, users=users, ip=ip)

@app.route("/login", methods=["POST"])
def login():
    u = request.form.get("u")
    p = request.form.get("p")
    if u == os.environ.get("WEB_ADMIN_USER") and p == os.environ.get("WEB_ADMIN_PASSWORD"):
        session["auth"] = True
    return redirect("/")

@app.route("/logout")
def logout():
    session.clear()
    return redirect("/")

@app.route("/add", methods=["POST"])
def add():
    user = request.form.get("user")
    pw = request.form.get("password")
    days = int(request.form.get("days", 30))
    exp_date = (datetime.now() + timedelta(days=days)).strftime("%Y-%m-%d")
    data = load_data()
    found = False
    for u in data:
        if u["user"] == user:
            u["password"] = pw
            u["expires"] = exp_date
            found = True
            break
    if not found:
        data.append({"user": user, "password": pw, "expires": exp_date})
    save_data(data)
    return redirect("/")

@app.route("/delete", methods=["POST"])
def delete():
    user = request.form.get("user")
    save_data([u for u in load_data() if u["user"] != user])
    return redirect("/")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8880, debug=False)
PY

# ===== Services Setup ===== (unchanged)
cat > /etc/systemd/system/zivpn.service << EOF
[Unit]
Description=ZIVPN UDP Server
After=network.target
[Service]
ExecStart=$BIN server -c $CFG
Restart=always
[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/zivpn-web.service << EOF
[Unit]
Description=ZIVPN Web UI
After=network.target
[Service]
EnvironmentFile=$ENVF
ExecStart=/usr/bin/python3 /etc/zivpn/web.py
Restart=always
[Install]
WantedBy=multi-user.target
EOF

# Networking (unchanged)
sysctl -w net.ipv4.ip_forward=1
iptables -t nat -D PREROUTING -p udp --dport 6000:19999 -j DNAT --to-destination :5667 2>/dev/null || true
iptables -t nat -A PREROUTING -p udp --dport 6000:19999 -j DNAT --to-destination :5667
iptables -t nat -D POSTROUTING -j MASQUERADE 2>/dev/null || true
iptables -t nat -A POSTROUTING -j MASQUERADE
ufw allow 5667/udp && ufw allow 8880/tcp && ufw allow 6000:19999/udp

systemctl daemon-reload
systemctl enable --now zivpn zivpn-web
systemctl restart zivpn-web

IP=$(hostname -I | awk '{print $1}')
echo -e "$LINE"
echo -e "${G}✅ အိုကေပြီ ကိုကို... IP အနှစ်သာရ ပြပေးထားပါပြီ${Z}"
echo -e "${C}Panel Link: ${Y}http://$IP:8880${Z}"
echo -e "$LINE"
