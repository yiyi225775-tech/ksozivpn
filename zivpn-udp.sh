#!/bin/bash
# ZIVPN UDP Server + Web UI (Myanmar) - Full Version
# Features: Top Slip Preview, Add User, User Management (Renew/Delete), VPS IP

set -euo pipefail

# ===== Pretty =====
B="\e[1;34m"; G="\e[1;32m"; Y="\e[1;33m"; R="\e[1;31m"; C="\e[1;36m"; Z="\e[0m"
MY_IP=$(curl -s ifconfig.me)

# ===== Paths & Files =====
mkdir -p /etc/zivpn
USERS="/etc/zivpn/users.json"
CONFIG_FILE="/etc/zivpn/config.json"
ENVF="/etc/zivpn/web.env"

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
    :root{ --bg:#f0f4f8; --primary:#2563eb; --ok:#10b981; --bad:#ef4444; --card:#fff; }
    body{ font-family:'Segoe UI',sans-serif; background:var(--bg); margin:0; padding:10px; display:flex; flex-direction:column; align-items:center; }
    .container{ width:100%; max-width:420px; }
    .card{ background:var(--card); border-radius:18px; padding:15px; box-shadow:0 4px 12px rgba(0,0,0,0.08); margin-bottom:15px; }
    
    /* Slip Preview Area */
    .slip-box { 
        background: white; border: 2px solid var(--primary); border-radius: 20px;
        padding: 20px; text-align: center; margin-bottom: 20px;
    }
    .slip-item { display: flex; justify-content: space-between; padding: 8px 0; border-bottom: 1px dashed #eee; font-size: 15px; }
    .slip-label { color: #64748b; font-weight: 600; }
    .slip-value { color: #1e293b; font-weight: 800; }

    input, select { width:100%; padding:12px; border:1px solid #e2e8f0; border-radius:10px; margin-bottom:10px; box-sizing:border-box; }
    .btn-main { width:100%; padding:14px; background:var(--primary); color:white; border:none; border-radius:12px; font-weight:800; cursor:pointer; }
    
    /* User List Style */
    .user-item { border-left: 5px solid var(--ok); padding: 10px; background: #f8fafc; border-radius: 8px; margin-bottom: 10px; position: relative; }
    .action-btns { display: flex; gap: 8px; margin-top: 8px; }
    .btn-renew { background: #dbeafe; color: var(--primary); border: none; padding: 6px 12px; border-radius: 6px; font-size: 12px; font-weight: 700; cursor: pointer; position: relative; }
    .btn-renew input[type="date"] { position: absolute; left: 0; top: 0; opacity: 0; width: 100%; height: 100%; cursor: pointer; }
    .btn-del { background: #fee2e2; color: var(--bad); border: none; padding: 6px 12px; border-radius: 6px; font-size: 12px; cursor: pointer; }
</style>
</head>
<body>
<div class="container">
    {% if not authed %}
    <div class="card" style="text-align:center; margin-top:50px;">
        <h3>KSO ADMIN LOGIN</h3>
        <form method="post" action="/login">
            <input name="u" placeholder="Username" required>
            <input name="p" type="password" placeholder="Password" required>
            <button class="btn-main">LOGIN</button>
        </form>
    </div>
    {% else %}

    <div id="capture-area" class="slip-box">
        <img src="{{logo}}" style="width:50px; border-radius:10px; margin-bottom:5px;">
        <h2 style="margin:0; color:var(--primary);">KSO VIP UDP</h2>
        <div style="font-size:10px; color:#94a3b8; margin-bottom:15px;">PREMIUM HIGH SPEED SERVER</div>
        <div class="slip-item"><span class="slip-label">Name:</span> <span id="vUser" class="slip-value">-</span></div>
        <div class="slip-item"><span class="slip-label">Password:</span> <span id="vPass" class="slip-value">-</span></div>
        <div class="slip-item"><span class="slip-label">Expired:</span> <span id="vDate" class="slip-value">-</span></div>
        <div class="slip-item"><span class="slip-label">Server IP:</span> <span class="slip-value">{{vps_ip}}</span></div>
        <p style="margin-top:15px; color:var(--ok); font-weight:bold; font-size:13px;">အသုံးပြုပေးမှုကို ကျေးဇူးတင်ပါတယ်!</p>
    </div>

    <div class="card">
        <form method="post" action="/add" id="mainForm">
            <input id="inUser" name="user" placeholder="နာမည်ထည့်ပါ" oninput="updateSlip()" required>
            <input id="inPass" name="password" placeholder="စကားဝှက်ထည့်ပါ" oninput="updateSlip()" required>
            <select id="inDays" name="days" onchange="updateSlip()">
                <option value="31">၁ လစာ (၃၁ ရက်)</option>
                <option value="62">၂ လစာ (၆၂ ရက်)</option>
            </select>
            <button type="button" onclick="saveAndDownload()" class="btn-main">သိမ်းဆည်းပြီး စလစ်ဒေါင်းမည်</button>
        </form>
    </div>

    <div class="card">
        <h4 style="margin:0 0 10px 0; color:#64748b;">အသုံးပြုသူများစာရင်း</h4>
        {% for u in users %}
        <div class="user-item">
            <div style="font-weight:800;">{{u.user}} <small style="font-weight:normal;">(PW: {{u.password}})</small></div>
            <div style="font-size:11px; color:#64748b;">ကုန်ရက်: {{u.expires}} ({{u.days_left}} ရက်ကျန်)</div>
            
            <div class="action-btns">
                <form method="post" action="/renew">
                    <input type="hidden" name="user" value="{{u.user}}">
                    <div class="btn-renew">
                        <i class="fa-solid fa-calendar-plus"></i> သက်တမ်းတိုး
                        <input type="date" name="new_date" onchange="this.form.submit()">
                    </div>
                </form>
                <form method="post" action="/delete" onsubmit="return confirm('ဖျက်မှာသေချာလား?')">
                    <input type="hidden" name="user" value="{{u.user}}">
                    <button class="btn-del"><i class="fa-solid fa-trash"></i> ဖျက်မည်</button>
                </form>
            </div>
        </div>
        {% endfor %}
    </div>

    <script>
    function updateSlip() {
        document.getElementById('vUser').innerText = document.getElementById('inUser').value || "-";
        document.getElementById('vPass').innerText = document.getElementById('inPass').value || "-";
        let d = new Date();
        d.setDate(d.getDate() + parseInt(document.getElementById('inDays').value));
        document.getElementById('vDate').innerText = d.toISOString().split('T')[0];
    }
    function saveAndDownload() {
        if(!document.getElementById('inUser').value) return alert("နာမည်ဖြည့်ပါ");
        html2canvas(document.getElementById('capture-area')).then(canvas => {
            const link = document.createElement('a');
            link.download = 'KSO_'+document.getElementById('inUser').value+'.png';
            link.href = canvas.toDataURL();
            link.click();
            setTimeout(() => { document.getElementById('mainForm').submit(); }, 500);
        });
    }
    updateSlip();
    </script>
    <div style="text-align:center;"><a href="/logout" style="color:var(--bad); text-decoration:none; font-size:12px;">LOGOUT</a></div>
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

def sync_vpn():
    users = get_users()
    try:
        with open(CONFIG_FILE, "r") as f: cfg = json.load(f)
        cfg['auth']['config'] = [u['password'] for u in users]
        with open(CONFIG_FILE, "w") as f: json.dump(cfg, f, indent=2)
        subprocess.run(["systemctl", "restart", "zivpn"])
    except: pass

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
    user, pw, days = request.form.get("user"), request.form.get("password"), int(request.form.get("days"))
    exp = (datetime.now() + timedelta(days=days)).strftime("%Y-%m-%d")
    data = get_users(); data.append({"user": user, "password": pw, "expires": exp})
    with open(USERS_FILE, "w") as f: json.dump(data, f); sync_vpn()
    return redirect("/")

@app.route("/renew", methods=["POST"])
def renew():
    target, new_date = request.form.get("user"), request.form.get("new_date")
    data = get_users()
    for u in data:
        if u['user'] == target: u['expires'] = new_date; break
    with open(USERS_FILE, "w") as f: json.dump(data, f); sync_vpn()
    return redirect("/")

@app.route("/delete", methods=["POST"])
def delete():
    target = request.form.get("user")
    data = [u for u in get_users() if u['user'] != target]
    with open(USERS_FILE, "w") as f: json.dump(data, f); sync_vpn()
    return redirect("/")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8880)
PY

# ===== Restart Service =====
systemctl daemon-reload
systemctl enable --now zivpn-web 2>/dev/null || systemctl restart zivpn-web

echo -e "\n${G}✅ User Management & Slip Preview အားလုံး ပေါင်းထည့်ပြီးပါပြီ!${Z}"
echo -e "${C}Web Panel:${Z} ${Y}http://$MY_IP:8880${Z}\n"
