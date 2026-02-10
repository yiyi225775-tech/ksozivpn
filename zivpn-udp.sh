#!/bin/bash
# ZIVPN FULL WEB PANEL (ALL-IN-ONE)
# နာမည်နှင့် စကားဝှက်ကို တစ်ခါတည်း သတ်မှတ်ပေးမည့် Version

set -euo pipefail

# ===== Get VPS IP =====
MY_IP=$(curl -s ifconfig.me)

# ===== Setup Directories =====
mkdir -p /etc/zivpn
USERS="/etc/zivpn/users.json"
CONFIG_FILE="/etc/zivpn/config.json"
ENVF="/etc/zivpn/web.env"

# ===== Admin Login သတ်မှတ်ခြင်း =====
clear
echo -e "\e[1;34m────────────────────────────────────────────────────────\e[0m"
echo -e "\e[1;33m🔒 Web Panel အတွက် Admin Login သတ်မှတ်ပါ\e[0m"
echo -e "\e[1;34m────────────────────────────────────────────────────────\e[0m"
read -p "Admin Username ပေးပါ: " WEB_USER
read -p "Admin Password ပေးပါ: " WEB_PASS
echo -e "\e[1;34m────────────────────────────────────────────────────────\e[0m"

# Env ဖိုင်ထဲသို့ သိမ်းဆည်းခြင်း
WEB_SECRET=$(openssl rand -hex 16)
echo "WEB_ADMIN_USER=${WEB_USER}" > "$ENVF"
echo "WEB_ADMIN_PASSWORD=${WEB_PASS}" >> "$ENVF"
echo "WEB_SECRET=${WEB_SECRET}" >> "$ENVF"

# ===== Web UI (web.py) =====
cat >/etc/zivpn/web.py <<PY
import os, json, subprocess
from flask import Flask, render_template_string, request, redirect, session
from datetime import datetime, timedelta

app = Flask(__name__)
app.secret_key = os.environ.get("WEB_SECRET", "kso-secret")

USERS_FILE = "/etc/zivpn/users.json"
CONFIG_FILE = "/etc/zivpn/config.json"
VPS_IP = "$MY_IP"
LOGO_URL = "https://raw.githubusercontent.com/KYAWSOEOO8/kso-script/main/icon.png"

HTML = """<!doctype html>
<html lang="my"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
<script src="https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js"></script>
<style>
    :root{ --bg:#f3f4f6; --primary:#2563eb; --ok:#10b981; --bad:#ef4444; --card:#fff; }
    body{ font-family:'Segoe UI',sans-serif; background:var(--bg); margin:0; padding:10px; display:flex; flex-direction:column; align-items:center; }
    .container{ width:100%; max-width:420px; }
    .card{ background:var(--card); border-radius:15px; padding:15px; box-shadow:0 4px 6px -1px rgba(0,0,0,0.1); margin-bottom:15px; border:1px solid #e5e7eb; }
    .slip-box { background: #fff; border: 2px solid var(--primary); border-radius: 20px; padding: 20px; text-align: center; position: relative; }
    .slip-title { font-size: 22px; font-weight: 900; color: var(--primary); margin: 0; }
    .slip-line { display: flex; justify-content: space-between; padding: 10px 0; border-bottom: 1px dashed #e5e7eb; }
    .s-lab { color: #6b7280; font-weight: 600; }
    .s-val { color: #111827; font-weight: 800; }
    input, select { width:100%; padding:12px; border:1px solid #d1d5db; border-radius:10px; margin-bottom:10px; box-sizing:border-box; font-size:14px; }
    .btn-main { width:100%; padding:14px; background:var(--primary); color:white; border:none; border-radius:10px; font-weight:bold; cursor:pointer; }
    .user-card { border-left: 5px solid var(--ok); padding: 10px; background: #fafafa; border-radius: 8px; margin-bottom: 10px; }
    .btn-group { display: flex; gap: 8px; margin-top: 10px; }
    .b-ren { background: #dbeafe; color: var(--primary); border: none; padding: 8px; border-radius: 6px; font-size: 12px; font-weight: bold; flex: 1; cursor: pointer; position: relative; text-align: center; }
    .b-ren input { position: absolute; left: 0; top: 0; opacity: 0; width: 100%; height: 100%; cursor: pointer; }
    .b-del { background: #fee2e2; color: var(--bad); border: none; padding: 8px; border-radius: 6px; font-size: 12px; font-weight: bold; flex: 1; cursor: pointer; }
</style>
</head>
<body>
<div class="container">
    {% if not authed %}
    <div class="card" style="margin-top:50px; text-align:center;">
        <img src="{{logo}}" style="width:60px; border-radius:15px;">
        <h2>ADMIN LOGIN</h2>
        <form method="post" action="/login">
            <input name="u" placeholder="Admin Username" required>
            <input name="p" type="password" placeholder="Admin Password" required>
            <button class="btn-main">LOGIN</button>
        </form>
    </div>
    {% else %}
    <div id="slip-area" class="slip-box">
        <img src="{{logo}}" style="width:50px; border-radius:10px;">
        <p class="slip-title">KSO VIP UDP</p>
        <div class="slip-line"><span class="s-lab">Name:</span> <span id="vUser" class="s-val">-</span></div>
        <div class="slip-line"><span class="s-lab">Password:</span> <span id="vPass" class="s-val">-</span></div>
        <div class="slip-line"><span class="s-lab">Expired:</span> <span id="vDate" class="s-val">-</span></div>
        <div class="slip-line"><span class="s-lab">Server IP:</span> <span class="s-val">{{vps_ip}}</span></div>
    </div>
    <div class="card">
        <form method="post" action="/add" id="addForm">
            <input id="inUser" name="user" placeholder="နာမည်ထည့်ပါ" oninput="up()" required>
            <input id="inPass" name="password" placeholder="စကားဝှက်ထည့်ပါ" oninput="up()" required>
            <select id="inDays" name="days" onchange="up()">
                <option value="31">၁ လစာ (၃၁ ရက်)</option>
                <option value="62">၂ လစာ (၆၂ ရက်)</option>
            </select>
            <button type="button" onclick="saveSlip()" class="btn-main">အကောင့်ဖွင့်ပြီး စလစ်ဒေါင်းမည်</button>
        </form>
    </div>
    <div class="card">
        <h3 style="font-size:16px;">အသုံးပြုသူများစာရင်း</h3>
        {% for u in users %}
        <div class="user-card">
            <b>{{u.user}}</b> (PW: {{u.password}})<br>
            <small>ကုန်ရက်: {{u.expires}} ({{u.days_left}} ရက်ကျန်)</small>
            <div class="btn-group">
                <form method="post" action="/renew" style="flex:1;"><input type="hidden" name="user" value="{{u.user}}"><div class="b-ren">သက်တမ်းတိုး<input type="date" name="new_date" onchange="this.form.submit()"></div></form>
                <form method="post" action="/delete" style="flex:1;"><input type="hidden" name="user" value="{{u.user}}"><button class="b-del">ဖျက်မည်</button></form>
            </div>
        </div>
        {% endfor %}
    </div>
    <script>
    function up() {
        document.getElementById('vUser').innerText = document.getElementById('inUser').value || "-";
        document.getElementById('vPass').innerText = document.getElementById('inPass').value || "-";
        let d = new Date(); d.setDate(d.getDate() + parseInt(document.getElementById('inDays').value));
        document.getElementById('vDate').innerText = d.toISOString().split('T')[0];
    }
    function saveSlip() {
        html2canvas(document.getElementById('slip-area')).then(canvas => {
            const link = document.createElement('a'); link.download = 'KSO.png'; link.href = canvas.toDataURL(); link.click();
            setTimeout(() => { document.getElementById('addForm').submit(); }, 600);
        });
    }
    up();
    </script>
    <div style="text-align:center;"><a href="/logout" style="font-size:12px; color:red;">LOGOUT</a></div>
    {% endif %}
</div>
</body></html>
"""

def get_users():
    try:
        with open(USERS_FILE, "r") as f: data = json.load(f)
    except: data = []
    for u in data:
        try:
            exp = datetime.strptime(u['expires'], "%Y-%m-%d")
            u['days_left'] = (exp - datetime.now()).days
        except: u['days_left'] = 0
    return data

@app.route("/")
def index():
    if not session.get('auth'): return render_template_string(HTML, authed=False, logo=LOGO_URL)
    return render_template_string(HTML, authed=True, logo=LOGO_URL, vps_ip=VPS_IP, users=get_users())

@app.route("/login", methods=["POST"])
def login():
    if request.form.get("u") == os.environ.get("WEB_ADMIN_USER") and request.form.get("p") == os.environ.get("WEB_ADMIN_PASSWORD"):
        session['auth'] = True
    return redirect("/")

@app.route("/logout")
def logout(): session.clear(); return redirect("/")

@app.route("/add", methods=["POST"])
def add():
    u, p, d = request.form.get("user"), request.form.get("password"), int(request.form.get("days"))
    exp = (datetime.now() + timedelta(days=d)).strftime("%Y-%m-%d")
    data = get_users(); data.append({"user": u, "password": p, "expires": exp})
    with open(USERS_FILE, "w") as f: json.dump(data, f)
    return redirect("/")

@app.route("/renew", methods=["POST"])
def renew():
    user, new_date = request.form.get("user"), request.form.get("new_date")
    data = get_users()
    for u in data:
        if u['user'] == user: u['expires'] = new_date; break
    with open(USERS_FILE, "w") as f: json.dump(data, f)
    return redirect("/")

@app.route("/delete", methods=["POST"])
def delete():
    user = request.form.get("user")
    data = [u for u in get_users() if u['user'] != user]
    with open(USERS_FILE, "w") as f: json.dump(data, f)
    return redirect("/")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8880)
PY

# ===== Service Setup & Launch =====
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
systemctl enable --now zivpn-web
systemctl restart zivpn-web

echo -e "\n\e[1;32m✅ အောင်မြင်စွာ တပ်ဆင်ပြီးပါပြီ!\e[0m"
echo -e "\e[1;36mURL:\e[0m \e[1;33mhttp://$MY_IP:8880\e[0m"
echo -e "\e[1;36mUsername:\e[0m \e[1;33m$WEB_USER\e[0m"
echo -e "\e[1;36mPassword:\e[0m \e[1;33m$WEB_PASS\e[0m\n"
