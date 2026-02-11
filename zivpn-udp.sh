#!/bin/bash
# ZIVPN UDP Server + Web UI (Myanmar) - Calendar Version
# Author mix: Zahid Islam + KSO tweaks

set -euo pipefail

# ===== Pretty =====
B="\e[1;34m"; G="\e[1;32m"; Y="\e[1;33m"; R="\e[1;31m"; C="\e[1;36m"; Z="\e[0m"
LINE="${B}────────────────────────────────────────────────────────${Z}"
say(){ echo -e "$1"; }

echo -e "\n$LINE\n${G}🌟 ZIVPN UDP-KSO (Calendar UI) မှ ရေးသားထားသည်${Z}\n$LINE"

# ===== Root check =====
if [ "$(id -u)" -ne 0 ]; then echo -e "${R}ဤ script ကို root အဖြစ် chạy ရပါမယ် (sudo -i)${Z}"; exit 1; fi

export DEBIAN_FRONTEND=noninteractive

# ===== Basic Packages =====
say "${Y}📦 Packages တင်နေပါတယ်...${Z}"
apt-get update -y >/dev/null
apt-get install -y curl ufw jq python3 python3-flask iproute2 conntrack ca-certificates openssl >/dev/null

# ===== Paths & Files =====
mkdir -p /etc/zivpn
BIN="/usr/local/bin/zivpn"
CFG="/etc/zivpn/config.json"
USERS="/etc/zivpn/users.json"
ENVF="/etc/zivpn/web.env"

# ===== Download Binary =====
say "${Y}⬇️ ZIVPN binary ကို ဒေါင်းနေပါတယ်...${Z}"
curl -fsSL -o "$BIN" "https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64"
chmod +x "$BIN"

# ===== SSL Certs =====
if [ ! -f /etc/zivpn/zivpn.crt ]; then
    openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
    -subj "/C=MM/ST=Yangon/L=Yangon/O=UPK/CN=zivpn" \
    -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt" >/dev/null 2>&1
fi

# ===== Web Login Setup =====
say "${Y}🔒 Web Admin Login UI သတ်မှတ်ချက်${Z}"
read -r -p "Admin Username: " WEB_USER
read -r -s -p "Admin Password: " WEB_PASS; echo
WEB_SECRET=$(python3 -c 'import secrets; print(secrets.token_hex(32))')

cat > "$ENVF" <<EOF
WEB_ADMIN_USER=${WEB_USER}
WEB_ADMIN_PASSWORD=${WEB_PASS}
WEB_SECRET=${WEB_SECRET}
EOF
chmod 600 "$ENVF"

# ===== Create Initial Files =====
[ -f "$USERS" ] || echo "[]" > "$USERS"
if [ ! -f "$CFG" ]; then
    echo '{"auth":{"mode":"passwords","config":["zi"]},"listen":":5667","cert":"/etc/zivpn/zivpn.crt","key":"/etc/zivpn/zivpn.key","obfs":"zivpn"}' > "$CFG"
fi

# ===== Generate Web UI (Python) =====
cat > /etc/zivpn/web.py <<'PY'
from flask import Flask, jsonify, render_template_string, request, redirect, url_for, session, make_response
import json, re, subprocess, os, tempfile, hmac
from datetime import datetime

USERS_FILE = "/etc/zivpn/users.json"
CONFIG_FILE = "/etc/zivpn/config.json"
LOGO_URL = "https://raw.githubusercontent.com/KYAWSOEOO8/kso-script/main/icon.png"

HTML = """<!doctype html>
<html lang="my"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
<script src="https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js"></script>
<style>
:root{ --bg:#f0f2f5; --fg:#1e293b; --primary:#2563eb; --ok:#10b981; --warn:#f59e0b; --bad:#ef4444; --card:#ffffff; --bd:#e2e8f0; --muted:#64748b; }
*{box-sizing: border-box; font-family: 'Segoe UI', sans-serif;}
body{ background:var(--bg); color:var(--fg); margin:0; padding:15px; display:flex; flex-direction:column; align-items:center; min-height:100vh; }
header{ width:100%; max-width:400px; text-align:center; margin-bottom:15px; }
.brand img{ width:70px; height:70px; border-radius:22px; border:3px solid #fff; box-shadow: 0 4px 15px rgba(0,0,0,0.1); margin-bottom:10px; }
.brand h1{ font-size:1.5em; margin:0; font-weight:900; color:var(--primary); text-transform:uppercase; }
.login-card{ margin-top:50px; background:#fff; padding:35px; border-radius:30px; width:100%; max-width:360px; text-align:center; box-shadow:0 20px 40px rgba(0,0,0,0.1); }
form.box{ background:var(--card); border-radius:25px; padding:22px; width:100%; max-width:400px; margin-bottom:20px; box-shadow:0 10px 25px rgba(0,0,0,0.05); }
.input-grp{ position:relative; margin-bottom: 15px; text-align: left; }
.input-grp i{ position:absolute; left:12px; top:38px; color:var(--primary); font-size:14px; }
label{ display:block; font-size:11px; color:var(--muted); margin-bottom:5px; font-weight:800; text-transform:uppercase; }
input{ width:100%; padding:12px 12px 12px 38px; border:2px solid var(--bd); border-radius:12px; font-size:14px; background:#f8fafc; }
.btn-primary{ background:var(--primary); color:#fff; border:none; width:100%; padding:15px; border-radius:15px; font-weight:800; cursor:pointer; display:flex; align-items:center; justify-content:center; gap:10px; }
.table-container{ width:100%; max-width:400px; }
table{ width:100%; border-collapse:separate; border-spacing: 0 10px; }
td{ background:var(--card); padding:15px; box-shadow: 0 2px 8px rgba(0,0,0,0.03); border-radius:18px; position:relative; }
.status-bar{ position:absolute; left:0; top:0; bottom:0; width:6px; border-radius:18px 0 0 18px; }
.bar-green{ background: var(--ok); } .bar-red{ background: var(--bad); }
#receipt{ position: fixed; left: -9999px; width: 350px; background: #fff; padding: 35px; border-radius: 25px; text-align: center; border: 1px solid #eee; }
.r-title{ color: var(--primary); font-size: 28px; font-weight: 900; border-bottom: 3px dashed var(--bd); padding-bottom: 15px; margin-bottom: 20px; }
.r-row{ display: flex; justify-content: space-between; margin-bottom: 12px; font-size: 16px; font-weight: 600; }
</style></head><body>
{% if not session.get('auth') %}
    <div class="login-card">
        <img src="{{ logo }}" style="width:85px; border-radius:22px; margin-bottom:15px;">
        <h2>LOGIN</h2>
        <form method="post" action="/login">
            <div class="input-grp"><label>Username</label><input name="u" required></div>
            <div class="input-grp"><label>Password</label><input name="p" type="password" required></div>
            <button class="btn-primary">အကောင့်ဝင်ရန်</button>
        </form>
    </div>
{% else %}
    <header>
        <div class="brand"><img src="{{ logo }}"><h1>KSO VIP PANEL</h1></div>
        <div style="margin-bottom:10px;"><a href="/logout" style="color:var(--bad); font-weight:bold; text-decoration:none;">LOGOUT</a></div>
    </header>
    <form method="post" action="/add" id="userForm" class="box">
        <div style="display:grid; grid-template-columns: 1fr 1fr; gap:10px;">
            <div class="input-grp"><label>နာမည်</label><i class="fa-solid fa-user"></i><input id="inUser" name="user" required></div>
            <div class="input-grp"><label>စကားဝှက်</label><i class="fa-solid fa-key"></i><input id="inPass" name="password" required></div>
        </div>
        <div style="display:grid; grid-template-columns: 1fr 1fr; gap:10px;">
            <div class="input-grp"><label>သက်တမ်းကုန်ရက်</label><i class="fa-solid fa-calendar"></i><input type="date" id="inExp" name="expires" required></div>
            <div class="input-grp"><label>PORT</label><i class="fa-solid fa-bolt"></i><input name="port" placeholder="Auto"></div>
        </div>
        <button type="button" onclick="handleSave()" class="btn-primary">သိမ်းဆည်းမည် (SAVE)</button>
    </form>

    <div id="receipt">
        <div class="r-title">KSO VIP</div>
        <div class="r-row"><span>နာမည်:</span> <span id="rUser"></span></div>
        <div class="r-row"><span>စကားဝှက်:</span> <span id="rPass"></span></div>
        <div class="r-row"><span>ကုန်ဆုံးရက်:</span> <span id="rDate"></span></div>
        <div style="margin-top:20px; color:var(--ok); font-weight:800;">ကျေးဇူးတင်ပါသည်</div>
    </div>

    <div class="table-container">
        <table><tbody>
            {% for u in users %}
            <tr>
                <td>
                    <div class="status-bar bar-green"></div>
                    <strong>{{u.user}}</strong><br>
                    <small style="color:var(--muted);"><i class="fa-solid fa-clock"></i> {{u.expires}}</small>
                    <form method="post" action="/delete" style="display:inline; float:right;">
                        <input type="hidden" name="user" value="{{u.user}}">
                        <button style="border:none; background:none; color:var(--bad); cursor:pointer;"><i class="fa-solid fa-trash"></i></button>
                    </form>
                </td>
            </tr>
            {% endfor %}
        </tbody></table>
    </div>

    <script>
    function handleSave() {
        const user = document.getElementById('inUser').value;
        const pass = document.getElementById('inPass').value;
        const exp = document.getElementById('inExp').value;
        if(!user || !pass || !exp) { alert("အချက်အလက်ပြည့်စုံစွာဖြည့်ပါ"); return; }
        
        document.getElementById('rUser').innerText = user;
        document.getElementById('rPass').innerText = pass;
        document.getElementById('rDate').innerText = exp;

        html2canvas(document.getElementById('receipt'), {scale: 2}).then(canvas => {
            const link = document.createElement('a');
            link.download = 'KSO_VIP_' + user + '.png';
            link.href = canvas.toDataURL("image/png");
            link.click();
            setTimeout(() => { document.getElementById('userForm').submit(); }, 500);
        });
    }
    </script>
{% endif %}
    users.append({"user":user,"password":password,"expires":expires,"port":port})
  save_users(users); sync_config_passwords()
  return jsonify({"ok":True})

@app.route("/favicon.ico", methods=["GET"])
def favicon(): return ("",204)

@app.errorhandler(405)
def handle_405(e): return redirect(url_for('index'))

if __name__ == "__main__":
  app.run(host="0.0.0.0", port=8880)
PY

# ===== Web systemd =====
cat >/etc/systemd/system/zivpn-web.service <<'EOF'
[Unit]
Description=ZIVPN Web Panel
After=network.target

[Service]
Type=simple
User=root
# Load optional web login credentials
EnvironmentFile=-/etc/zivpn/web.env
ExecStart=/usr/bin/python3 /etc/zivpn/web.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# ===== Networking: forwarding + DNAT + MASQ + UFW =====
echo -e "${Y}😁ရပါပြီနော်..ကိုကို😘😘😘...${Z}"
sysctl -w net.ipv4.ip_forward=1 >/dev/null
grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.conf || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf

IFACE=$(ip -4 route ls | awk '/default/ {print $5; exit}')
[ -n "${IFACE:-}" ] || IFACE=eth0
# DNAT 6000:19999/udp -> :5667
iptables -t nat -C PREROUTING -i "$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667 2>/dev/null || \
iptables -t nat -A PREROUTING -i "$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667
# MASQ out
iptables -t nat -C POSTROUTING -o "$IFACE" -j MASQUERADE 2>/dev/null || \
iptables -t nat -A POSTROUTING -o "$IFACE" -j MASQUERADE

ufw allow 5667/udp >/dev/null 2>&1 || true
ufw allow 6000:19999/udp >/dev/null 2>&1 || true
ufw allow 8880/tcp >/dev/null 2>&1 || true
ufw reload >/dev/null 2>&1 || true

# ===== CRLF sanitize =====
sed -i 's/\r$//' /etc/zivpn/web.py /etc/systemd/system/zivpn.service /etc/systemd/system/zivpn-web.service || true

# ===== Enable services =====
systemctl daemon-reload
systemctl enable --now zivpn.service
systemctl enable --now zivpn-web.service

IP=$(hostname -I | awk '{print $1}')
echo -e "\n$LINE\n${G}VPS-IP-COPYလုပ်ပါ${Z}"
echo -e "${C}ဘာကြည့်နေတာလဲ    :${Z} ${Y}http://$IP:8880${Z}"
echo -e "${C}ရပါပြီဆို  :${Z} ${Y}/etc/zivpn/users.json${Z}"
echo -e "${C}မယုံရင် :${Z} ${Y}/etc/zivpn/config.json${Z}"
echo -e "${C}လော့အင်ကြည့်ကွာ    :${Z} ${Y}systemctl status|restart zivpn  •  systemctl status|restart zivpn-web${Z}"
echo -e "$LINE"
