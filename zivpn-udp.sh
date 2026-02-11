#!/bin/bash
# ZIVPN-KSO EXPERT V2 (Renew Feature Added)
set -euo pipefail

# ===== Colors =====
B="\e[1;34m"; G="\e[1;32m"; Y="\e[1;33m"; R="\e[1;31m"; C="\e[1;36m"; Z="\e[0m"
LINE="${B}────────────────────────────────────────────────────────${Z}"

# Clean old services
systemctl stop zivpn zivpn-web 2>/dev/null || true

echo -e "\n$LINE\n${G}🌟 KSO VIP (Expert V2) Renew System စတင်တပ်ဆင်နေပြီ...${Z}\n$LINE"

# ===== Install Requirements =====
apt-get update -y >/dev/null
apt-get install -y curl jq python3 python3-flask iproute2 conntrack openssl ufw >/dev/null

mkdir -p /etc/zivpn
BIN="/usr/local/bin/zivpn"
[ -f "/etc/zivpn/users.json" ] || echo "[]" > "/etc/zivpn/users.json"

# Download Binary
curl -fsSL -o "$BIN" "https://github.com/zahidbd2/udp-zivpn/releases/latest/download/udp-zivpn-linux-amd64"
chmod +x "$BIN"

# Set Admin Credentials
WEB_SECRET=$(openssl rand -hex 16)
[ -f "/etc/zivpn/web.env" ] || {
    echo "WEB_ADMIN_USER=admin" > /etc/zivpn/web.env
    echo "WEB_ADMIN_PASSWORD=admin123" >> /etc/zivpn/web.env
}
echo "WEB_SECRET=${WEB_SECRET}" >> /etc/zivpn/web.env

# Generate SSL
openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 -subj "/C=MM/CN=zivpn" -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt" >/dev/null 2>&1

# ===== Updated Python Web Script with Renew =====
cat > /etc/zivpn/web.py << 'PY'
import os, json, subprocess, hmac
from flask import Flask, render_template_string, request, redirect, url_for, session
from datetime import datetime, timedelta

app = Flask(__name__)
app.secret_key = os.environ.get("WEB_SECRET", "kso-secret-2026")
USERS_FILE = "/etc/zivpn/users.json"

def get_vps_ip():
    try: return subprocess.check_output(["hostname", "-I"]).decode().split()[0]
    except: return "127.0.0.1"

def load_users():
    if not os.path.exists(USERS_FILE): return []
    try:
        with open(USERS_FILE, "r") as f:
            data = json.load(f)
            for u in data:
                try:
                    dt = datetime.strptime(u['expires'], "%Y-%m-%d") - datetime.now()
                    u['days_left'] = max(0, dt.days + 1)
                except: u['days_left'] = 0
            return data
    except: return []

HTML = """
<!DOCTYPE html>
<html lang="my">
<head>
    <meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <style>
        :root{ --bg:#f0f4f8; --p:#2563eb; --card:#fff; --ok:#10b981; --bad:#ef4444; --warn:#f59e0b; }
        body{ font-family:sans-serif; background:var(--bg); margin:0; padding:10px; display:flex; flex-direction:column; align-items:center;}
        .container{ width:100%; max-width:480px; }
        .card{ background:var(--card); padding:15px; border-radius:15px; box-shadow:0 4px 6px rgba(0,0,0,0.05); margin-bottom:15px; border:1px solid #e2e8f0; }
        input{ width:100%; padding:12px; border:1px solid #cbd5e1; border-radius:10px; margin-bottom:10px; box-sizing:border-box; }
        .btn-p{ background:var(--p); color:#fff; border:none; width:100%; padding:12px; border-radius:10px; font-weight:bold; cursor:pointer; }
        .btn-renew{ background:var(--warn); color:white; border:none; padding:5px 10px; border-radius:6px; cursor:pointer; font-size:11px; }
        .copy-btn{ cursor:pointer; color:var(--p); margin-left:5px; font-size:13px; }
        .status-pill{ padding:2px 8px; border-radius:8px; color:#fff; font-size:11px; font-weight:bold; }
        table{ width:100%; border-collapse:collapse; margin-top:10px; }
        th{ text-align:left; font-size:11px; color:#64748b; padding-bottom:8px; border-bottom:1px solid #f1f5f9; }
        td{ padding:12px 0; border-bottom:1px solid #f1f5f9; font-size:13px; }
        .toast { position:fixed; bottom:20px; background:#1e293b; color:white; padding:8px 16px; border-radius:8px; display:none; z-index:100; }
    </style>
</head>
<body>
    <div id="toast" class="toast">Copied!</div>
    <div class="container">
        {% if not authed %}
            <div class="card" style="margin-top:100px; text-align:center;">
                <h2 style="color:var(--p)">ADMIN LOGIN</h2>
                <form method="post" action="/login">
                    <input name="u" placeholder="Username" required>
                    <input name="p" type="password" placeholder="Password" required>
                    <button class="btn-p">LOGIN</button>
                </form>
            </div>
        {% else %}
            <div style="text-align:center; margin-bottom:15px;">
                <h2 style="margin:0; color:var(--p);">KSO VIP PANEL</h2>
                <span style="font-size:12px;">Server IP: <b>{{vps_ip}}</b> <i class="fa-regular fa-copy copy-btn" onclick="copyText('{{vps_ip}}')"></i></span>
            </div>

            <div class="card">
                <form method="post" action="/add">
                    <div style="display:grid; grid-template-columns: 1fr 1fr; gap:10px;">
                        <div><label style="font-size:12px;">နာမည်</label><input name="user" required></div>
                        <div><label style="font-size:12px;">စကားဝှက်</label><input name="password" required></div>
                    </div>
                    <div>
                        <label style="font-size:12px;">သက်တမ်းကုန်မည့်ရက် (ပြက္ကဒိန်)</label>
                        <input type="date" name="exp_date" id="inDate" required>
                    </div>
                    <button class="btn-p">အသစ်ထည့်မည်</button>
                </form>
            </div>

            <div class="card">
                <table>
                    <thead>
                        <tr>
                            <th>User/IP</th>
                            <th>စကားဝှက်</th>
                            <th>သက်တမ်း</th>
                            <th>လုပ်ဆောင်ချက်</th>
                        </tr>
                    </thead>
                    <tbody>
                        {% for u in users %}
                        <tr>
                            <td>
                                <b>{{u.user}}</b> <i class="fa-regular fa-copy copy-btn" onclick="copyText('{{u.user}}')"></i><br>
                                <small style="color:#666;">{{vps_ip}}</small>
                            </td>
                            <td>
                                <code>{{u.password}}</code> <i class="fa-regular fa-copy copy-btn" onclick="copyText('{{u.password}}')"></i>
                            </td>
                            <td>
                                <span class="status-pill" style="background:{% if u.days_left > 7 %}var(--ok){% else %}var(--bad){% endif %};">
                                    {{u.days_left}} ရက်
                                </span><br>
                                <small style="font-size:10px;">{{u.expires}}</small>
                            </td>
                            <td align="right">
                                <form method="post" action="/renew" style="display:inline; margin-right:5px;">
                                    <input type="hidden" name="user" value="{{u.user}}">
                                    <button class="btn-renew" title="နောက်ထပ် ရက် ၃၀ တိုးမည်"><i class="fa-solid fa-clock-rotate-left"></i> တိုး</button>
                                </form>
                                <form method="post" action="/delete" style="display:inline;" onsubmit="return confirm('ဖျက်မှာ သေချာလား?')">
                                    <input type="hidden" name="user" value="{{u.user}}">
                                    <button style="border:none; background:none; color:var(--bad); cursor:pointer;"><i class="fa-solid fa-trash-can"></i></button>
                                </form>
                            </td>
                        </tr>
                        {% endfor %}
                    </tbody>
                </table>
            </div>
            <p style="text-align:center;"><a href="/logout" style="color:var(--bad); text-decoration:none; font-size:12px;">Logout</a></p>
        {% endif %}
    </div>

    <script>
        function copyText(txt) {
            navigator.clipboard.writeText(txt);
            const t = document.getElementById('toast');
            t.style.display = 'block';
            setTimeout(() => { t.style.display = 'none'; }, 2000);
        }
        window.onload = function() {
            if(document.getElementById('inDate')){
                let today = new Date();
                today.setDate(today.getDate() + 30);
                document.getElementById('inDate').value = today.toISOString().split('T')[0];
            }
        };
    </script>
</body>
</html>
"""

@app.route("/")
def index():
    if not session.get("auth"): return render_template_string(HTML, authed=False)
    return render_template_string(HTML, authed=True, users=load_users(), vps_ip=get_vps_ip())

@app.route("/login", methods=["POST"])
def login():
    if hmac.compare_digest(request.form.get("u"), os.environ.get("WEB_ADMIN_USER")) and \
       hmac.compare_digest(request.form.get("p"), os.environ.get("WEB_ADMIN_PASSWORD")):
        session["auth"] = True
    return redirect("/")

@app.route("/logout")
def logout(): session.clear(); return redirect("/")

@app.route("/add", methods=["POST"])
def add_user():
    user, pw, exp_date = request.form.get("user"), request.form.get("password"), request.form.get("exp_date")
    users = [u for u in load_users() if u["user"] != user]
    users.append({"user":user, "password":pw, "expires":exp_date})
    with open(USERS_FILE, "w") as f: json.dump(users, f, indent=2)
    return redirect("/")

@app.route("/renew", methods=["POST"])
def renew_user():
    user_name = request.form.get("user")
    users = load_users()
    for u in users:
        if u["user"] == user_name:
            # လက်ရှိကုန်မည့်ရက်စွဲကို ယူပြီး ရက် ၃၀ ပေါင်းထည့်သည်
            current_exp = datetime.strptime(u['expires'], "%Y-%m-%d")
            new_exp = (current_exp + timedelta(days=30)).strftime("%Y-%m-%d")
            u['expires'] = new_exp
            break
    with open(USERS_FILE, "w") as f: json.dump(users, f, indent=2)
    return redirect("/")

@app.route("/delete", methods=["POST"])
def delete():
    user = request.form.get("user")
    users = [u for u in load_users() if u["user"] != user]
    with open(USERS_FILE, "w") as f: json.dump(users, f, indent=2)
    return redirect("/")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8880)
PY

# ===== Systemd & Networking =====
cat >/etc/systemd/system/zivpn.service <<EOF
[Unit]
Description=ZIVPN Server
After=network.target
[Service]
ExecStart=$BIN server -c /etc/zivpn/config.json
Restart=always
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

# Network Setup
sysctl -w net.ipv4.ip_forward=1
IFACE=$(ip -4 route ls | awk '/default/ {print $5; exit}')
iptables -t nat -A PREROUTING -i "$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667
iptables -t nat -A POSTROUTING -o "$IFACE" -j MASQUERADE
ufw allow 8880/tcp && ufw allow 5667/udp && ufw allow 6000:19999/udp

systemctl daemon-reload
systemctl enable --now zivpn zivpn-web
systemctl restart zivpn zivpn-web

IP=$(hostname -I | awk '{print $1}')
echo -e "\n$LINE\n${G}✅ Renew System တပ်ဆင်ပြီးပါပြီ${Z}"
echo -e "${C}Web Panel :${Z} ${Y}http://$IP:8880${Z}"
echo -e "$LINE"
