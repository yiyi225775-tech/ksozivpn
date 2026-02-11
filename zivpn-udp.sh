#!/bin/bash
# ZIVPN UDP Server + Expert Web UI (Myanmar) - Fixed Version
set -euo pipefail

# ===== Colors =====
B="\e[1;34m"; G="\e[1;32m"; Y="\e[1;33m"; R="\e[1;31m"; C="\e[1;36m"; Z="\e[0m"
LINE="${B}────────────────────────────────────────────────────────${Z}"

# Stop old services
systemctl stop zivpn zivpn-web 2>/dev/null || true

echo -e "\n$LINE\n${G}🌟 ZIVPN UDP-KSO (Expert Edition) ကို စတင်သွင်းနေပြီ...${Z}\n$LINE"

# ===== Packages =====
apt-get update -y >/dev/null
apt-get install -y curl python3 python3-flask openssl ufw jq >/dev/null

# ===== Folders & Binary =====
mkdir -p /etc/zivpn
BIN="/usr/local/bin/zivpn"
[ -f "/etc/zivpn/users.json" ] || echo "[]" > "/etc/zivpn/users.json"

curl -fsSL -o "$BIN" "https://github.com/zahidbd2/udp-zivpn/releases/latest/download/udp-zivpn-linux-amd64"
chmod +x "$BIN"

# Admin Setup
WEB_SECRET=$(openssl rand -hex 16)
[ -f "/etc/zivpn/web.env" ] || {
    echo "WEB_ADMIN_USER=admin" > /etc/zivpn/web.env
    echo "WEB_ADMIN_PASSWORD=admin123" >> /etc/zivpn/web.env
}
echo "WEB_SECRET=${WEB_SECRET}" >> /etc/zivpn/web.env

# SSL & Config
echo '{"auth":{"mode":"passwords","config":["zi"]},"listen":":5667","cert":"/etc/zivpn/zivpn.crt","key":"/etc/zivpn/zivpn.key","obfs":"zivpn"}' > /etc/zivpn/config.json
openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 -subj "/C=MM/CN=zivpn" -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt" >/dev/null 2>&1

# ===== Python Web Panel (Fixed UI & Design) =====
cat > /etc/zivpn/web.py << 'PY'
import os, json, subprocess
from flask import Flask, render_template_string, request, redirect, url_for, session
from datetime import datetime

app = Flask(__name__)
app.secret_key = os.environ.get("WEB_SECRET", "kso-secret")
USERS_FILE = "/etc/zivpn/users.json"
CONFIG_FILE = "/etc/zivpn/config.json"

def get_vps_ip():
    try: return subprocess.check_output(["hostname", "-I"]).decode().split()[0]
    except: return "127.0.0.1"

VPS_IP = get_vps_ip()

def load_data():
    try:
        with open(USERS_FILE, "r") as f:
            users = json.load(f)
            for u in users:
                dt = datetime.strptime(u['expires'], "%Y-%m-%d") - datetime.now()
                u['days'] = max(0, dt.days + 1)
            return users
    except: return []

def sync():
    users = load_data()
    pws = [u["password"] for u in users] or ["zi"]
    with open(CONFIG_FILE, "r") as f: cfg = json.load(f)
    cfg["auth"]["config"] = pws
    with open(CONFIG_FILE, "w") as f: json.dump(cfg, f)
    subprocess.run(["systemctl", "restart", "zivpn.service"])

HTML = """
<!DOCTYPE html>
<html lang="my">
<head>
    <meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <style>
        :root { --p:#2563eb; --bg:#f8fafc; --text:#1e293b; --ok:#10b981; --bad:#ef4444; }
        body { font-family: 'Segoe UI', sans-serif; background: var(--bg); color: var(--text); margin:0; padding:15px; }
        .container { max-width:450px; margin:auto; }
        .card { background:white; padding:20px; border-radius:15px; box-shadow:0 4px 15px rgba(0,0,0,0.05); margin-bottom:15px; }
        .btn { padding:12px; border:none; border-radius:10px; cursor:pointer; font-weight:bold; width:100%; transition:0.3s; }
        .btn-p { background:var(--p); color:white; }
        input { width:100%; padding:12px; margin:8px 0; border:1px solid #e2e8f0; border-radius:10px; box-sizing:border-box; }
        /* Slip Design Like Image 1 */
        .slip-box { background: white; padding: 25px; border-radius: 12px; text-align: left; margin: 10px 0; border: 1px solid #f1f5f9; box-shadow: 0 10px 25px -5px rgba(0,0,0,0.1); }
        .slip-title { text-align: center; color: var(--p); font-weight: bold; font-size: 26px; margin-bottom: 5px; }
        .slip-line { border-bottom: 2px dashed #e2e8f0; margin: 15px 0; }
        .slip-row { display: flex; justify-content: space-between; margin-bottom: 12px; font-size: 16px; }
        .slip-label { color: #64748b; font-weight: 500; }
        .slip-value { font-weight: bold; color: #1e293b; }
        .slip-footer { text-align: center; color: #10b981; font-weight: bold; font-size: 18px; margin-top: 15px; }
        .status { padding:4px 10px; border-radius:20px; color:white; font-size:11px; font-weight:bold; }
        table { width:100%; border-collapse:collapse; }
        td { padding:12px 8px; border-bottom:1px solid #f1f5f9; }
        .copy-icon { cursor:pointer; color: var(--p); margin-left:8px; }
    </style>
</head>
<body>
    <div class="container">
        {% if not authed %}
            <div class="card" style="text-align:center; margin-top:80px;">
                <h2 style="color:var(--p)">KSO VIP ADMIN</h2>
                <form method="post" action="/login">
                    <input name="u" placeholder="Admin Name" required>
                    <input name="p" type="password" placeholder="Password" required>
                    <button class="btn btn-p">LOGIN PANEL</button>
                </form>
            </div>
        {% else %}
            <div style="text-align:center; margin-bottom:15px;">
                <h3 style="margin:0; color:var(--p)">KSO VIP MANAGER</h3>
                <small>VPS IP: {{ip}}</small>
            </div>

            <div class="slip-box" id="capture">
                <div class="slip-title">KSO VIP</div>
                <div class="slip-line"></div>
                <div class="slip-row">
                    <span class="slip-label">နာမည်:</span>
                    <span class="slip-value" id="sU">---</span>
                </div>
                <div class="slip-row">
                    <span class="slip-label">စကားဝှက်:</span>
                    <span class="slip-value" id="sP">---</span>
                </div>
                <div class="slip-row">
                    <span class="slip-label">ကုန်ရက်:</span>
                    <span class="slip-value" id="sD">---</span>
                </div>
                <div class="slip-line"></div>
                <div class="slip-footer">ကျေးဇူးတင်ပါသည်</div>
            </div>

            <div class="card">
                <form method="post" action="/add">
                    <input name="user" id="iU" placeholder="Account Name" oninput="up()" required>
                    <input name="password" id="iP" placeholder="Password" oninput="up()" required>
                    <input type="date" name="exp" id="iD" onchange="up()" required>
                    <button class="btn btn-p">SAVE ACCOUNT</button>
                </form>
            </div>

            <div class="card" style="padding:10px; overflow-x:auto;">
                <table>
                    {% for u in users %}
                    <tr>
                        <td>
                            <b>{{u.user}}</b><br>
                            <small>{{u.password}}</small>
                        </td>
                        <td align="right">
                            <span class="status" style="background:{% if u.days > 7 %}var(--ok){% else %}var(--bad){% endif %}">
                                {{u.days}} d
                            </span>
                        </td>
                        <td align="right">
                            <i class="fa-solid fa-copy copy-icon" onclick="cp('{{u.user}}','{{u.password}}','{{u.expires}}')"></i>
                            <form method="post" action="/del" style="display:inline;" onsubmit="return confirm('Delete?')">
                                <input type="hidden" name="user" value="{{u.user}}">
                                <button style="border:none; background:none; color:var(--bad); cursor:pointer;"><i class="fa-solid fa-trash-can"></i></button>
                            </form>
                        </td>
                    </tr>
                    {% endfor %}
                </table>
            </div>
            <center><a href="/logout" style="color:var(--bad); text-decoration:none; font-size:12px;">Logout Panel</a></center>
        {% endif %}
    </div>
    <script>
        function up(){
            document.getElementById('sU').innerText = document.getElementById('iU').value || '---';
            document.getElementById('sP').innerText = document.getElementById('iP').value || '---';
            document.getElementById('sD').innerText = document.getElementById('iD').value || '---';
        }
        function cp(u,p,d){
            const t = `🌐 KSO VIP TICKET\\nနာမည်: ${u}\\nစကားဝှက်: ${p}\\nကုန်ရက်: ${d}\\nကျေးဇူးတင်ပါသည်`;
            navigator.clipboard.writeText(t); alert("Copied!");
        }
        window.onload = function(){
            if(document.getElementById('iD')){
                let d = new Date(); d.setDate(d.getDate() + 30);
                document.getElementById('iD').value = d.toISOString().split('T')[0];
                up();
            }
        }
    </script>
</body>
</html>
"""

@app.route("/")
def index():
    if not session.get("authed"): return render_template_string(HTML, authed=False)
    return render_template_string(HTML, authed=True, users=load_data(), ip=VPS_IP)

@app.route("/login", methods=["POST"])
def login():
    if request.form.get("u") == os.environ.get("WEB_ADMIN_USER") and request.form.get("p") == os.environ.get("WEB_ADMIN_PASSWORD"):
        session["authed"] = True
    return redirect("/")

@app.route("/logout")
def logout(): session.clear(); return redirect("/")

@app.route("/add", methods=["POST"])
def add():
    u, p, e = request.form.get("user"), request.form.get("password"), request.form.get("exp")
    users = [x for x in load_data() if x["user"] != u]
    users.append({"user": u, "password": p, "expires": e})
    with open(USERS_FILE, "w") as f: json.dump(users, f)
    sync(); return redirect("/")

@app.route("/del", methods=["POST"])
def delete():
    u = request.form.get("user")
    users = [x for x in load_data() if x["user"] != u]
    with open(USERS_FILE, "w") as f: json.dump(users, f)
    sync(); return redirect("/")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8880)
PY

# ===== Service Registration =====
cat >/etc/systemd/system/zivpn.service <<EOF
[Unit]
Description=ZIVPN UDP Server
After=network.target
[Service]
ExecStart=$BIN server -c /etc/zivpn/config.json
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
EnvironmentFile=/etc/zivpn/web.env
ExecStart=/usr/bin/python3 /etc/zivpn/web.py
Restart=always
[Install]
WantedBy=multi-user.target
EOF

# Networking
sysctl -w net.ipv4.ip_forward=1 >/dev/null
ufw allow 5667/udp && ufw allow 6000:19999/udp && ufw allow 8880/tcp >/dev/null

# Final Start
systemctl daemon-reload
systemctl enable --now zivpn zivpn-web
systemctl restart zivpn zivpn-web

IP=$(hostname -I | awk '{print $1}')
echo -e "\n$LINE\n${G}✅ Panel အောင်မြင်စွာ Update ဖြစ်သွားပါပြီ${Z}"
echo -e "${C}Web Link :${Z} ${Y}http://$IP:8880${Z}"
echo -e "$LINE\n"
