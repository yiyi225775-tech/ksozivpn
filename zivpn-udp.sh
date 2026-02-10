#!/bin/bash
# ZIVPN FULL WEB PANEL - RENEW TO SLIP FORM VERSION

set -euo pipefail

MY_IP=$(curl -s ifconfig.me)
mkdir -p /etc/zivpn
USERS="/etc/zivpn/users.json"
ENVF="/etc/zivpn/web.env"

# Admin Login သတ်မှတ်ခြင်း
clear
echo -e "\e[1;34m────────────────────────────────────────────────────────\e[0m"
echo -e "\e[1;33m🔒 Web Panel အတွက် Admin Login သတ်မှတ်ပါ\e[0m"
echo -e "\e[1;34m────────────────────────────────────────────────────────\e[0m"
read -p "Admin Username: " WEB_USER
read -p "Admin Password: " WEB_PASS
echo -e "\e[1;34m────────────────────────────────────────────────────────\e[0m"

echo "WEB_ADMIN_USER=${WEB_USER}" > "$ENVF"
echo "WEB_ADMIN_PASSWORD=${WEB_PASS}" >> "$ENVF"
echo "WEB_SECRET=$(openssl rand -hex 16)" >> "$ENVF"

# ===== Web UI (web.py) =====
cat >/etc/zivpn/web.py <<PY
import os, json, subprocess
from flask import Flask, render_template_string, request, redirect, session
from datetime import datetime, timedelta

app = Flask(__name__)
app.secret_key = os.environ.get("WEB_SECRET", "kso-secret")
USERS_FILE = "/etc/zivpn/users.json"
VPS_IP = "$MY_IP"
LOGO_URL = "https://raw.githubusercontent.com/KYAWSOEOO8/kso-script/main/icon.png"

HTML = """<!doctype html>
<html lang="my"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
<script src="https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js"></script>
<style>
    :root{ --bg:#f1f5f9; --primary:#2563eb; --ok:#10b981; --bad:#ef4444; --card:#fff; --bd:#e2e8f0; }
    body{ font-family:'Segoe UI',sans-serif; background:var(--bg); margin:0; padding:10px; display:flex; flex-direction:column; align-items:center; }
    .container{ width:100%; max-width:420px; }
    .card{ background:var(--card); border-radius:18px; padding:15px; box-shadow:0 4px 12px rgba(0,0,0,0.05); margin-bottom:15px; border:1px solid var(--bd); }
    .slip-box { background: #fff; border: 2px solid var(--primary); border-radius: 20px; padding: 20px; text-align: center; position: relative; }
    .slip-title { font-size: 20px; font-weight: 900; color: var(--primary); margin: 5px 0; }
    .slip-line { display: flex; justify-content: space-between; padding: 10px 0; border-bottom: 1px dashed var(--bd); font-size: 14px; }
    .s-lab { color: #64748b; font-weight: 600; }
    .s-val { color: #1e293b; font-weight: 800; }
    input { width:100%; padding:12px; border:1px solid var(--bd); border-radius:10px; margin-bottom:10px; box-sizing:border-box; font-size: 14px; outline:none; transition: 0.3s; }
    input:focus { border-color: var(--primary); box-shadow: 0 0 5px rgba(37,99,235,0.2); }
    .btn-main { width:100%; padding:14px; background:var(--primary); color:white; border:none; border-radius:12px; font-weight:800; cursor:pointer; }
    .user-card { border-left: 5px solid var(--ok); padding: 12px; background: #fdfdfd; border-radius: 12px; margin-bottom: 12px; border: 1px solid var(--bd); }
    .btn-group { display: flex; gap: 8px; margin-top: 10px; }
    .b-ren { background: #dbeafe; color: var(--primary); border: none; padding: 10px; border-radius: 8px; font-size: 12px; font-weight: 700; flex: 1; cursor: pointer; text-align: center; display:flex; align-items:center; justify-content:center; gap:5px; }
    .b-del { background: #fee2e2; color: var(--bad); border: none; padding: 10px; border-radius: 8px; font-size: 12px; font-weight: 700; flex: 1; cursor: pointer; display:flex; align-items:center; justify-content:center; gap:5px; }
</style>
</head>
<body>
<div class="container">
    {% if not authed %}
    <div class="card" style="margin-top:60px; text-align:center;">
        <img src="{{logo}}" style="width:70px; border-radius:18px;">
        <h2 style="color:var(--primary);">KSO LOGIN</h2>
        <form method="post" action="/login">
            <input name="u" placeholder="Admin Username" required>
            <input name="p" type="password" placeholder="Admin Password" required>
            <button class="btn-main">LOGIN</button>
        </form>
    </div>
    {% else %}

    <div id="slip-area" class="slip-box">
        <img src="{{logo}}" style="width:50px; border-radius:12px;">
        <p class="slip-title">KSO VIP UDP</p>
        <div class="slip-line"><span class="s-lab">User:</span> <span id="vUser" class="s-val">-</span></div>
        <div class="slip-line"><span class="s-lab">Pass:</span> <span id="vPass" class="s-val">-</span></div>
        <div class="slip-line"><span class="s-lab">Exp:</span> <span id="vDate" class="s-val">-</span></div>
        <div class="slip-line"><span class="s-lab">IP:</span> <span class="s-val">{{vps_ip}}</span></div>
    </div>

    <div class="card" style="margin-top:15px;" id="input-section">
        <h3 id="form-title" style="font-size:15px; margin:0 0 12px 0; color:var(--primary);"><i class="fa-solid fa-user-plus"></i> အကောင့်အသစ်ဖွင့်ရန်</h3>
        <form method="post" action="/add" id="addForm">
            <input id="inUser" name="user" placeholder="နာမည်ထည့်ပါ" oninput="up()" required>
            <input id="inPass" name="password" placeholder="စကားဝှက်ထည့်ပါ" oninput="up()" required>
            <input type="date" id="inDate" name="expires" oninput="up()" required>
            <button type="button" onclick="saveSlip()" class="btn-main"><i class="fa-solid fa-file-arrow-down"></i> အကောင့်သိမ်းပြီး စလစ်ဒေါင်းမည်</button>
        </form>
    </div>

    <div class="card">
        <h3 style="font-size:15px; margin:0 0 15px 0; color:#475569;"><i class="fa-solid fa-users"></i> အသုံးပြုသူများစာရင်း</h3>
        {% for u in users %}
        <div class="user-card">
            <div style="display:flex; justify-content:space-between;">
                <b>{{u.user}}</b>
                <span style="font-size:11px; background:#f1f5f9; padding:2px 8px; border-radius:10px;">PW: {{u.password}}</span>
            </div>
            <div style="font-size:11px; color:#64748b; margin-top:5px;">
                <i class="fa-solid fa-clock"></i> {{u.expires}} <b>({{u.days_left}} ရက်ကျန်)</b>
            </div>
            <div class="btn-group">
                <button class="b-ren" onclick="loadToForm('{{u.user}}', '{{u.password}}', '{{u.expires}}')">
                    <i class="fa-solid fa-arrows-rotate"></i> သက်တမ်းတိုး / စလစ်ထုတ်
                </button>
                <form method="post" action="/delete" style="flex:1;" onsubmit="return confirm('ဖျက်မှာသေချာလား?')">
                    <input type="hidden" name="user" value="{{u.user}}">
                    <button class="b-del"><i class="fa-solid fa-trash-can"></i> ဖျက်မည်</button>
                </form>
            </div>
        </div>
        {% endfor %}
    </div>

    <script>
    // User အချက်အလက်များကို Form ဆီသို့ ပြန်တင်ပေးခြင်း
    function loadToForm(user, pass, date) {
        document.getElementById('inUser').value = user;
        document.getElementById('inPass').value = pass;
        document.getElementById('inDate').value = date;
        document.getElementById('form-title').innerHTML = '<i class="fa-solid fa-arrows-rotate"></i> အကောင့်သက်တမ်းတိုးခြင်း';
        document.getElementById('input-section').scrollIntoView({behavior: 'smooth'});
        up();
    }

    window.onload = function() {
        let d = new Date(); d.setDate(d.getDate() + 30);
        document.getElementById('inDate').value = d.toISOString().split('T')[0];
        up();
    };

    function up() {
        document.getElementById('vUser').innerText = document.getElementById('inUser').value || "-";
        document.getElementById('vPass').innerText = document.getElementById('inPass').value || "-";
        document.getElementById('vDate').innerText = document.getElementById('inDate').value || "-";
    }

    function saveSlip() {
        if(!document.getElementById('inUser').value) return alert("နာမည်ထည့်ပါ");
        html2canvas(document.getElementById('slip-area')).then(canvas => {
            const link = document.createElement('a'); 
            link.download = 'KSO_'+document.getElementById('inUser').value+'.png';
            link.href = canvas.toDataURL(); 
            link.click();
            setTimeout(() => { document.getElementById('addForm').submit(); }, 600);
        });
    }
    </script>
    <div style="text-align:center; margin-top:10px;"><a href="/logout" style="font-size:12px; color:var(--bad); text-decoration:none;"><i class="fa-solid fa-power-off"></i> LOGOUT</a></div>
    {% endif %}
</div>
</body></html>
"""

def get_users():
    try:
        with open(USERS_FILE, "r") as f: data = json.load(f)
    except: data = []
    # Sort to remove duplicates when updating
    unique_data = {u['user']: u for u in data}
    final_list = list(unique_data.values())
    for u in final_list:
        try:
            exp = datetime.strptime(u['expires'], "%Y-%m-%d")
            u['days_left'] = (exp - datetime.now()).days
        except: u['days_left'] = 0
    return final_list

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
    u, p, exp = request.form.get("user"), request.form.get("password"), request.form.get("expires")
    data = get_users()
    # If user exists, update it, otherwise append
    new_data = [user for user in data if user['user'] != u]
    new_data.append({"user": u, "password": p, "expires": exp})
    with open(USERS_FILE, "w") as f: json.dump(new_data, f)
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

# ===== Restart Service =====
systemctl daemon-reload
systemctl enable --now zivpn-web
systemctl restart zivpn-web

echo -e "\n\e[1;32m✅ Logic အသစ်ဖြင့် အောင်မြင်စွာ ပြင်ဆင်ပြီးပါပြီ!\e[0m"
echo -e "\e[1;36mWeb URL:\e[0m \e[1;33mhttp://$MY_IP:8880\e[0m\n"
