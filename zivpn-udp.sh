#!/bin/bash
# ZIVPN UDP Server + FIXED UI - ပြက္ခဒိန် + ကုန်ရက် + Copy FIX
set -euo pipefail

# ===== Colors =====
B="e[1;34m"; G="e[1;32m"; Y="e[1;33m"; R="e[1;31m"; C="e[1;36m"; Z="e[0m"
LINE="${B}────────────────────────────────────────────────────────${Z}"

echo -e "
$LINE
${G}🌟 ZIVPN KSO UI - ပြက္ခဒိန် + Copy FIX${Z}
$LINE"

# Root check
if [ "$(id -u)" -ne 0 ]; then echo -e "${R}Root user ဖြင့် run ပါ${Z}"; exit 1; fi

apt-get update -y && apt-get install -y curl ufw jq python3 python3-flask iproute2 conntrack openssl

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

[ -f "$CFG" ] || echo '{"listen":":5667","auth":{"mode":"passwords","config":["zi"]},"obfs":"zivpn"}' > "$CFG"
[ -f "$USERS" ] || echo "[]" > "$USERS"

# Web Admin Setup
echo -e "${Y}Setup Web Login${Z}"
read -r -p "Username: " WEB_USER
read -r -s -p "Password: " WEB_PASS; echo
WEB_SECRET=$(openssl rand -hex 16)

cat > "$ENVF" << ENVE
WEB_ADMIN_USER=$WEB_USER
WEB_ADMIN_PASSWORD=$WEB_PASS
WEB_SECRET=$WEB_SECRET
ENVE
chmod 600 "$ENVF"

# ===== PERFECT UI - ပြက္ခဒိန် + ကုန်ရက် + Full Copy =====
cat > /etc/zivpn/web.py << 'PY'
from flask import Flask, request, redirect, render_template_string, session
import os, json, subprocess
from datetime import datetime, timedelta

app = Flask(__name__)
app.secret_key = os.environ.get("WEB_SECRET", "kso123")
USERS_FILE = "/etc/zivpn/users.json"
CONFIG_FILE = "/etc/zivpn/config.json"

def load_users():
    try: 
        users = json.load(open(USERS_FILE))
        now = datetime.now()
        for u in users:
            exp_date = datetime.strptime(u['expires'], '%Y-%m-%d')
            days_left = max(0, (exp_date - now).days + 1)
            u['days_left'] = days_left
            u['status'] = 'good' if days_left > 10 else 'warn' if days_left > 3 else 'bad'
        return users
    except: return []

def save_users(users):
    json.dump(users, open(USERS_FILE, 'w'), indent=2)
    try:
        with open(CONFIG_FILE, 'r') as f:
            cfg = json.load(f)
        cfg["auth"]["config"] = [u["password"] for u in users if "password" in u]
        with open(CONFIG_FILE, 'w') as f:
            json.dump(cfg, f, indent=2)
        subprocess.run(["systemctl", "restart", "zivpn"], check=False)
    except: pass

HTML = '''
<!DOCTYPE html>
<html>
<head>
    <title>KSO VPN PANEL</title>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        * { margin:0; padding:0; box-sizing:border-box; }
        body { 
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); 
            min-height:100vh; font-family: -apple-system, sans-serif; 
            padding:20px; display:flex; align-items:center; justify-content:center;
        }
        .panel { 
            background:white; border-radius:20px; box-shadow:0 20px 40px rgba(0,0,0,0.1); 
            max-width:500px; width:100%; padding:30px; 
        }
        h1 { text-align:center; color:#333; margin-bottom:10px; font-size:24px; }
        .ip-box { 
            background:#1a1a2e; color:#00f5ff; padding:15px; border-radius:12px; 
            text-align:center; font-family:monospace; font-size:16px; margin-bottom:25px; 
            cursor:pointer; transition:all 0.3s;
        }
        .ip-box:hover { background:#16213e; transform:scale(1.02); }
        .form-group { margin-bottom:20px; }
        label { display:block; color:#555; font-weight:500; margin-bottom:8px; }
        input { 
            width:100%; padding:12px; border:2px solid #e1e5e9; border-radius:10px; 
            font-size:16px; transition:border-color 0.3s;
        }
        input:focus { outline:none; border-color:#667eea; }
        /* ပြက္ခဒိန်အတွက် Style အသစ် */
        input[type="date"] {
            cursor: pointer;
            text-transform: uppercase;
        }
        .btn { 
            width:100%; padding:14px; border:none; border-radius:10px; font-size:16px; 
            font-weight:600; cursor:pointer; transition:all 0.3s;
        }
        .btn-primary { background:#667eea; color:white; }
        .btn-primary:hover { background:#5a67d8; transform:translateY(-2px); }
        .user-item { 
            background:#f8f9ff; border:2px solid #e1e5e9; border-radius:12px; 
            padding:20px; margin-bottom:15px;
        }
        .user-line { 
            display:flex; justify-content:space-between; align-items:center; 
            margin-bottom:8px; font-family:monospace; font-size:14px;
        }
        .copy-btn { 
            background:#10b981; color:white; border:none; padding:8px 12px; 
            border-radius:6px; cursor:pointer; font-size:12px; transition:all 0.3s;
        }
        .copy-btn:hover { background:#059669; }
        .days-row { display:flex; gap:10px; margin-top:10px; }
        .btn-small { padding:8px 12px; font-size:14px; width:100%; }
        .status { 
            padding:4px 8px; border-radius:20px; font-size:12px; font-weight:600; 
            margin-left:10px;
        }
        .status.good { background:#d4edda; color:#155724; }
        .status.warn { background:#fff3cd; color:#856404; }
        .status.bad { background:#f8d7da; color:#721c24; }
        .del-btn { background:#ef4444; color:white; border:none; padding:6px 10px; 
            border-radius:6px; cursor:pointer; }
        .del-btn:hover { background:#dc2626; }
    </style>
</head>
<body>
    <div class="panel">
        <h1>🔐 KSO VPN PANEL</h1>
        <div class="ip-box" onclick="copyIP('{{ip}}')">
            📡 SERVER IP: {{ip}}
        </div>

        {% if not session.auth %}
        <form method="POST" action="/login">
            <div class="form-group">
                <label>👤 Admin Username</label>
                <input name="user" required>
            </div>
            <div class="form-group">
                <label>🔑 Admin Password</label>
                <input name="pass" type="password" required>
            </div>
            <button class="btn btn-primary">🚀 အကောင့်ဝင်ရန်</button>
        </form>
        {% else %}
        
        <form method="POST" action="/add">
            <div class="form-group">
                <label>👤 VPN Username</label>
                <input name="user" id="newuser" placeholder="နာမည်ရိုက်ပါ" required>
            </div>
            <div class="form-group">
                <label>🔑 VPN Password</label>
                <input name="pass" id="newpass" placeholder="လျှို့ဝှက်နံပါတ်" required>
            </div>
            
            <div class="form-group">
                <label>📅 သက်တမ်းကုန်မည့်ရက်စွဲ (Expired Date)</label>
                <input type="date" name="expire_date" id="expire_date" required>
                
                <div class="days-row">
                    <button type="button" class="btn btn-small btn-primary" onclick="addMonths(1)">+ 1 လ တိုးမည်</button>
                    <button type="button" class="btn btn-small btn-primary" onclick="addMonths(2)">+ 2 လ တိုးမည်</button>
                </div>
            </div>
            
            <button class="btn btn-primary">➕ အကောင့်သစ် သိမ်းမည်</button>
        </form>

        <hr style="margin: 25px 0; border: 0; border-top: 1px solid #eee;">

        {% for u in users %}
        <div class="user-item">
            <div class="user-line">
                <span>👤 <b>{{u.user}}</b></span>
                <span class="status {{u.status}}">{{u.days_left}} ရက် ကျန်</span>
            </div>
            <div class="user-line">
                <span>🔑 {{u.password}}</span>
                <button class="copy-btn" onclick="copyPass('{{u.password}}')">Copy Pass</button>
            </div>
            <div class="user-line">
                <span>📅 {{u.expires}}</span>
                <button class="copy-btn" onclick="copyFull('{{ip}}','{{u.user}}','{{u.password}}','{{u.expires}}')">Full Copy</button>
            </div>
            <div style="text-align: right; margin-top: 10px;">
                <form method="POST" action="/delete" style="display:inline" onsubmit="return confirm('ဖျက်မှာ သေချာပါသလား?')">
                    <input type="hidden" name="user" value="{{u.user}}">
                    <button type="submit" class="del-btn">🗑️ Delete User</button>
                </form>
            </div>
        </div>
        {% endfor %}

        <br><a href="/logout" style="color:#ef4444; text-align:center; display:block; text-decoration: none; font-weight: bold;">🚪 Logout Panel</a>
        {% endif %}
    </div>

    <script>
    // စာမျက်နှာစဖွင့်တာနဲ့ ဒီနေ့ရက်စွဲကို ပြက္ခဒိန်မှာ Default ပြပေးရန်
    window.onload = function() {
        if(document.getElementById('expire_date')) {
            let today = new Date();
            today.setMonth(today.getMonth() + 1); // Default ကို ၁ လ ပေါင်းပေးထားမည်
            document.getElementById('expire_date').value = today.toISOString().split('T')[0];
        }
    };

    function addMonths(m) {
        let dateField = document.getElementById('expire_date');
        let date = new Date(); // ယနေ့မှစတွက်ရန်
        date.setMonth(date.getMonth() + m);
        dateField.value = date.toISOString().split('T')[0];
    }

    function copyIP(ip) {
        navigator.clipboard.writeText(ip).then(() => alert('✅ IP Copied!'));
    }
    function copyPass(pass) {
        navigator.clipboard.writeText(pass).then(() => alert('✅ Password Copied!'));
    }
    function copyFull(ip, user, pass, expires) {
        const fullConfig = `IP: ${ip}\nUser: ${user}\nPass: ${pass}\nExpires: ${expires}`;
        navigator.clipboard.writeText(fullConfig).then(() => {
            alert('✅ FULL CONFIG COPIED!\n\nIP + User + Pass + ကုန်ရက်');
        });
    }
    </script>
</body>
</html>
'''

@app.route('/')
def index():
    ip = request.host.split(':')[0]
    if not session.get('auth'):
        return render_template_string(HTML, session={'auth':False}, ip=ip, users=[])
    
    users = load_users()
    return render_template_string(HTML, session={'auth':True}, ip=ip, users=users)

@app.route('/login', methods=['POST'])
def login():
    if (request.form['user'] == os.environ.get('WEB_ADMIN_USER') and 
        request.form['pass'] == os.environ.get('WEB_ADMIN_PASSWORD')):
        session['auth'] = True
    return redirect('/')

@app.route('/logout')
def logout():
    session.clear()
    return redirect('/')

@app.route('/add', methods=['POST'])
def add():
    users = load_users()
    user = request.form['user']
    password = request.form['pass']
    days = int(request.form['days'])
    expires = (datetime.now() + timedelta(days=days)).strftime('%Y-%m-%d')
    
    for u in users:
        if u['user'] == user:
            u['password'] = password
            u['expires'] = expires
            break
    else:
        users.append({
            'user': user,
            'password': password,
            'expires': expires
        })
    
    save_users(users)
    return redirect('/')

@app.route('/delete', methods=['POST'])
def delete():
    user = request.form['user']
    users = [u for u in load_users() if u['user'] != user]
    save_users(users)
    return redirect('/')

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8880, debug=False)
PY

# Services
cat > /etc/systemd/system/zivpn.service << EOF
[Unit]
Description=ZIVPN UDP Server
After=network.target
[Service]
ExecStart=/usr/local/bin/zivpn server -c /etc/zivpn/config.json
Restart=always
[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/zivpn-web.service << EOF
[Unit]
Description=ZIVPN Web UI
After=network.target
[Service]
EnvironmentFile=/etc/zivpn/web.env
ExecStart=/usr/bin/python3 /etc/zivpn/web.py
Restart=always
[Install]
WantedBy=multi-user.target
EOF

# Networking
sysctl -w net.ipv4.ip_forward=1
iptables -t nat -A PREROUTING -p udp --dport 6000:19999 -j DNAT --to-destination :5667 2>/dev/null || true
iptables -t nat -A POSTROUTING -j MASQUERADE 2>/dev/null || true
ufw allow 5667/udp 8880/tcp 6000:19999/udp

systemctl daemon-reload
systemctl enable --now zivpn zivpn-web

IP=$(hostname -I | awk '{print $1}')
echo -e "${G}✅ ပြက္ခဒိန် + ကုန်ရက် + Full Copy FIX!${Z}"
echo -e "${C}Panel: ${Y}http://$IP:8880${Z}"
echo -e "$LINE"
