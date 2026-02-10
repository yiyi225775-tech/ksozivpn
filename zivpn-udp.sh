#!/bin/bash
# ZIVPN UDP Server + Web UI (Myanmar) - KSO OPTIMIZED VERSION
set -euo pipefail

# ===== Pretty Colors =====
B="\e[1;34m"; G="\e[1;32m"; Y="\e[1;33m"; R="\e[1;31m"; C="\e[1;36m"; Z="\e[0m"
LINE="${B}────────────────────────────────────────────────────────${Z}"

say(){ echo -e "$1"; }
echo -e "\n$LINE\n${G}🌟 ZIVPN UDP-KSO အပြည့်အစုံ Setup စတင်နေပါပြီ${Z}\n$LINE"

# 1. Root check
if [ "$(id -u)" -ne 0 ]; then say "${R}Error: root user ဖြင့်သာ run ပါ!${Z}"; exit 1; fi

# 2. Update & Install Packages
say "${Y}📦 လိုအပ်သော Packages များ တင်နေပါတယ်...${Z}"
apt-get update -y >/dev/null
apt-get install -y curl ufw jq python3 python3-flask python3-pip iproute2 conntrack openssl ca-certificates >/dev/null

# 3. Create Directory & Paths
mkdir -p /etc/zivpn
BIN="/usr/local/bin/zivpn"
CFG="/etc/zivpn/config.json"
USERS="/etc/zivpn/users.json"
ENVF="/etc/zivpn/web.env"

# 4. Download ZIVPN binary
say "${Y}⬇️ ZIVPN Binary ဒေါင်းလုဒ်ဆွဲနေပါတယ်...${Z}"
URL="https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64"
curl -fsSL -o "$BIN" "$URL" || curl -fsSL -o "$BIN" "https://github.com/zahidbd2/udp-zivpn/releases/latest/download/udp-zivpn-linux-amd64"
chmod +x "$BIN"

# 5. SSL Certs
if [ ! -f /etc/zivpn/zivpn.crt ]; then
    openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
    -subj "/C=MM/ST=Yangon/L=Yangon/O=KSO/CN=zivpn" \
    -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt" >/dev/null 2>&1
fi

# 6. Admin Credentials Setup
say "${Y}🔒 Web Admin အတွက် Username နှင့် Password သတ်မှတ်ပါ${Z}"
read -p "Admin Username: " WEB_USER
read -s -p "Admin Password: " WEB_PASS; echo
WEB_SECRET=$(openssl rand -hex 16)

echo "WEB_ADMIN_USER=${WEB_USER}" > "$ENVF"
echo "WEB_ADMIN_PASSWORD=${WEB_PASS}" >> "$ENVF"
echo "WEB_SECRET=${WEB_SECRET}" >> "$ENVF"
chmod 600 "$ENVF"

# 7. Initial Config
if [ ! -f "$CFG" ]; then
    echo '{"auth":{"mode":"passwords","config":["zi"]},"listen":":5667","cert":"/etc/zivpn/zivpn.crt","key":"/etc/zivpn/zivpn.key","obfs":"zivpn"}' > "$CFG"
fi
[ -f "$USERS" ] || echo "[]" > "$USERS"

# 8. Web UI (Python Code)
cat >/etc/zivpn/web.py <<'PY'
import os, json, subprocess, hmac, tempfile, re
from flask import Flask, render_template_string, request, redirect, url_for, session, jsonify, make_response
from datetime import datetime, timedelta

app = Flask(__name__)
app.secret_key = os.environ.get("WEB_SECRET", "kso-secret")
USERS_FILE = "/etc/zivpn/users.json"
CONFIG_FILE = "/etc/zivpn/config.json"
LOGO_URL = "https://raw.githubusercontent.com/KYAWSOEOO8/kso-script/main/icon.png"

HTML = """<!doctype html>
<html lang="my">
<head>
    <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <script src="https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js"></script>
    <style>
        :root{ --bg:#f0f2f5; --primary:#2563eb; --card:#fff; }
        body{ background:var(--bg); font-family: sans-serif; display:flex; flex-direction:column; align-items:center; padding:20px; }
        .card{ background:var(--card); padding:25px; border-radius:20px; width:100%; max-width:400px; box-shadow:0 10px 20px rgba(0,0,0,0.1); text-align:center; }
        input{ width:100%; padding:12px; margin:8px 0; border:1px solid #ddd; border-radius:10px; }
        .btn-p{ background:var(--primary); color:#fff; border:none; width:100%; padding:12px; border-radius:10px; font-weight:bold; cursor:pointer; }
        .user-item{ background:#fff; margin-top:10px; padding:15px; border-radius:12px; display:flex; justify-content:space-between; align-items:center; border-left:5px solid #10b981; box-shadow:0 2px 5px rgba(0,0,0,0.05); }
        #receipt{ position:fixed; left:-9999px; background:#fff; padding:30px; width:300px; text-align:center; border-radius:15px; }
    </style>
</head>
<body>
    <div class="card">
        <img src="{{ logo }}" style="width:70px; border-radius:15px;">
        <h2>KSO VIP PANEL</h2>
        {% if not session.get('auth') %}
            <form method="POST" action="/login">
                <input name="u" placeholder="Admin Username" required>
                <input name="p" type="password" placeholder="Password" required>
                <button class="btn-p">LOGIN</button>
            </form>
        {% else %}
            <form method="POST" action="/add" id="userForm">
                <input name="user" id="inUser" placeholder="နာမည်" required>
                <input name="password" id="inPass" placeholder="စကားဝှက်" required>
                <input name="expires" id="inDays" placeholder="ရက်ပေါင်း (ဥပမာ 30)" required>
                <button type="button" onclick="handleSave()" class="btn-p">SAVE & GENERATE</button>
            </form>
            <div style="margin-top:20px; text-align:left; width:100%;">
                {% for u in users %}
                <div class="user-item">
                    <div><b>{{ u.user }}</b><br><small>Exp: {{ u.expires }}</small></div>
                    <form method="POST" action="/delete"><input type="hidden" name="user" value="{{ u.user }}"><button style="color:red; border:none; background:none; cursor:pointer;"><i class="fa-solid fa-trash"></i></button></form>
                </div>
                {% endfor %}
            </div>
            <br><a href="/logout" style="text-decoration:none; color:gray;">Logout</a>
        {% endif %}
    </div>

    <div id="receipt">
        <h2 style="color:#2563eb;">KSO VIP</h2>
        <p>User: <span id="rUser"></span></p>
        <p>Pass: <span id="rPass"></span></p>
        <p>Exp: <span id="rDate"></span></p>
        <hr><p>Thank You!</p>
    </div>

    <script>
    function handleSave() {
        const user = document.getElementById('inUser').value;
        const pass = document.getElementById('inPass').value;
        const days = document.getElementById('inDays').value || "30";
        if(!user || !pass) return alert("ဖြည့်ပါ");
        document.getElementById('rUser').innerText = user;
        document.getElementById('rPass').innerText = pass;
        let d = new Date(); d.setDate(d.getDate() + parseInt(days));
        document.getElementById('rDate').innerText = d.toISOString().split('T')[0];
        
        html2canvas(document.getElementById('receipt')).then(canvas => {
            const link = document.createElement('a');
            link.download = 'KSO_'+user+'.png';
            link.href = canvas.toDataURL();
            link.click();
            document.getElementById('userForm').submit();
        });
    }
    </script>
</body>
</html>
"""

def sync_vpn():
    try:
        with open(USERS_FILE, "r") as f: users = json.load(f)
        with open(CONFIG_FILE, "r") as f: config = json.load(f)
        config["auth"]["config"] = [u["password"] for u in users]
        with open(CONFIG_FILE, "w") as f: json.dump(config, f, indent=2)
        subprocess.run(["systemctl", "restart", "zivpn"], check=False)
    except Exception as e: print(e)

@app.route("/")
def index():
    if not os.path.exists(USERS_FILE):
        with open(USERS_FILE, "w") as f: json.dump([], f)
    with open(USERS_FILE, "r") as f: users = json.load(f)
    return render_template_string(HTML, users=users, logo=LOGO_URL)

@app.route("/login", methods=["POST"])
def login():
    if request.form.get("u") == os.environ.get("WEB_ADMIN_USER") and \
       request.form.get("p") == os.environ.get("WEB_ADMIN_PASSWORD"):
        session["auth"] = True
    return redirect(url_for("index"))

@app.route("/logout")
def logout(): session.clear(); return redirect(url_for("index"))

@app.route("/add", methods=["POST"])
def add():
    if not session.get("auth"): return redirect("/")
    u, p, d = request.form.get("user"), request.form.get("password"), request.form.get("expires")
    exp = (datetime.now() + timedelta(days=int(d))).strftime("%Y-%m-%d")
    with open(USERS_FILE, "r") as f: users = json.load(f)
    users.append({"user": u, "password": p, "expires": exp})
    with open(USERS_FILE, "w") as f: json.dump(users, f)
    sync_vpn()
    return redirect("/")

@app.route("/delete", methods=["POST"])
def delete():
    if not session.get("auth"): return redirect("/")
    u = request.form.get("user")
    with open(USERS_FILE, "r") as f: users = json.load(f)
    users = [user for user in users if user["user"] != u]
    with open(USERS_FILE, "w") as f: json.dump(users, f)
    sync_vpn()
    return redirect("/")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8880)
PY

# 9. Services & Networking
say "${Y}🌐 Networking Setup လုပ်နေပါတယ်...${Z}"
sysctl -w net.ipv4.ip_forward=1 >/dev/null
echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf

IFACE=$(ip -4 route ls | awk '/default/ {print $5; exit}')
iptables -t nat -A PREROUTING -i "$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667
iptables -t nat -A POSTROUTING -o "$IFACE" -j MASQUERADE

ufw allow 8880/tcp >/dev/null
ufw allow 5667/udp >/dev/null
ufw allow 6000:19999/udp >/dev/null

# 10. Systemd Files
cat >/etc/systemd/system/zivpn.service <<EOF
[Unit]
Description=ZIVPN UDP Server
After=network.target
[Service]
ExecStart=$BIN server -c $CFG
Restart=always
User=root
EOF

cat >/etc/systemd/system/zivpn-web.service <<EOF
[Unit]
Description=ZIVPN Web Panel
After=network.target
[Service]
EnvironmentFile=$ENVF
ExecStart=/usr/bin/python3 /etc/zivpn/web.py
Restart=always
User=root
EOF

systemctl daemon-reload
systemctl enable --now zivpn zivpn-web

# Final Output
IP=$(curl -s ifconfig.me)
say "$LINE"
say "${G}✅ အောင်မြင်စွာ တပ်ဆင်ပြီးပါပြီ!${Z}"
say "${C}Web Panel :${Z} ${Y}http://$IP:8880${Z}"
say "${C}User Management:${Z} ${Y}/etc/zivpn/users.json${Z}"
say "$LINE"
