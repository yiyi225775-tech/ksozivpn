#!/bin/bash
# ZIVPN UDP Server + Web UI (Myanmar)
# Author mix: Zahid Islam (udp-zivpn) + KSO tweaks + KSO polish
# Features: apt-guard, binary fetch fallback, UFW rules, DNAT+MASQ, sysctl forward,
#           Flask 1.x-compatible Web UI (auto-refresh 120s), users.json <-> config.json mirror sync,
#           per-user Online/Offline via conntrack, expires accepts "YYYY-MM-DD" OR days "30",
#           Web UI: Header logo + title + Messenger button, Delete button per user, clean styling,
#           Login UI (form-based session, logo included) with /etc/zivpn/web.env credentials.
#           +++ Added: ONE-TIME KEY GATE (consume from built-in API before installing)

set -euo pipefail

# ===== Pretty =====
B="\e[1;34m"; G="\e[1;32m"; Y="\e[1;33m"; R="\e[1;31m"; C="\e[1;36m"; M="\e[1;35m"; Z="\e[0m"
LINE="${B}────────────────────────────────────────────────────────${Z}"
say(){ echo -e "$1"; }

echo -e "\n$LINE\n${G}🌟 ZIVPN UDP-KSO မှ ရေးသားထားသည်${Z}\n$LINE"

# ===== Root check =====
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${R}ဤ script ကို root အဖြစ် chạy ရပါမယ် (sudo -i)${Z}"; exit 1
fi

export DEBIAN_FRONTEND=noninteractive

# ===== apt guards =====
wait_for_apt() {
  echo -e "${Y}⏳ apt ပိတ်မချင်း စောင့်နေပါတယ်...${Z}"
  for _ in $(seq 1 60); do
    if pgrep -x apt-get >/dev/null || pgrep -x apt >/dev/null || pgrep -f 'apt.systemd.daily' >/dev/null || pgrep -x unattended-upgrade >/dev/null; then
      sleep 5
    else
      return 0
    fi
  done
  echo -ે "${Y}⚠️ apt timers ကို ယာယီရပ်နေပါတယ်${Z}"
  systemctl stop --now unattended-upgrades.service 2>/dev/null || true
  systemctl stop --now apt-daily.service apt-daily.timer 2>/dev/null || true
  systemctl stop --now apt-daily-upgrade.service apt-daily-upgrade.timer 2>/dev/null || true
}
apt_guard_start(){
  wait_for_apt
  CNF_CONF="/etc/apt/apt.conf.d/50command-not-found"
  if [ -f "$CNF_CONF" ]; then mv "$CNF_CONF" "${CNF_CONF}.disabled"; CNF_DISABLED=1; else CNF_DISABLED=0; fi
}
apt_guard_end(){
  dpkg --configure -a >/dev/null 2>&1 || true
  apt-get -f install -y >/dev/null 2>&1 || true
  if [ "${CNF_DISABLED:-0}" = "1" ] && [ -f "${CNF_CONF}.disabled" ]; then mv "${CNF_CONF}.disabled" "$CNF_CONF"; fi
}

# ===== Packages =====
say "${Y}📦 Packages တင်နေပါတယ်...${Z}"
apt_guard_start
apt-get update -y -o APT::Update::Post-Invoke-Success::= -o APT::Update::Post-Invoke::= >/dev/null
apt-get install -y curl ufw jq python3 python3-flask python3-apt iproute2 conntrack ca-certificates >/dev/null || {
  apt-get install -y -o DPkg::Lock::Timeout=60 python3-apt >/dev/null || true
  apt-get install -y curl ufw jq python3 python3-flask iproute2 conntrack ca-certificates >/dev/null
}
apt_guard_end

# stop old services to avoid text busy
systemctl stop zivpn.service 2>/dev/null || true
systemctl stop zivpn-web.service 2>/dev/null || true

# ===== Paths =====
BIN="/usr/local/bin/zivpn"
CFG="/etc/zivpn/config.json"
USERS="/etc/zivpn/users.json"
ENVF="/etc/zivpn/web.env"
mkdir -p /etc/zivpn

# ===== Download ZIVPN binary =====
say "${Y}⬇️ ZIVPN binary ကို ဒေါင်းနေပါတယ်...${Z}"
PRIMARY_URL="https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64"
FALLBACK_URL="https://github.com/zahidbd2/udp-zivpn/releases/latest/download/udp-zivpn-linux-amd64"
TMP_BIN="$(mktemp)"
if ! curl -fsSL -o "$TMP_BIN" "$PRIMARY_URL"; then
  echo -e "${Y}Primary URL မရ — latest ကို စမ်းပါတယ်...${Z}"
  curl -fSL -o "$TMP_BIN" "$FALLBACK_URL"
fi
install -m 0755 "$TMP_BIN" "$BIN"
rm -f "$TMP_BIN"

# ===== Base config =====
if [ ! -f "$CFG" ]; then
  say "${Y}🧩 config.json ဖန်တီးနေပါတယ်...${Z}"
  curl -fsSL -o "$CFG" "https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/config.json" || echo '{}' > "$CFG"
fi

# ===== Certs =====
if [ ! -f /etc/zivpn/zivpn.crt ] || [ ! -f /etc/zivpn/zivpn.key ]; then
  say "${Y}🔐 SSL စိတျဖိုင်တွေ ဖန်တီးနေပါတယ်...${Z}"
  openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
    -subj "/C=MM/ST=Yangon/L=Yangon/O=UPK/OU=Net/CN=zivpn" \
    -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt" >/dev/null 2>&1
fi

# ===== Web Admin (Login UI credentials) =====
say "${Y}🔒 Web Admin Login UI ထည့်မလား? (လစ်: မဖိတ်)${Z}"
read -r -p "Web Admin Username (Enter=disable): " WEB_USER
if [ -n "${WEB_USER:-}" ]; then
  read -r -s -p "Web Admin Password: " WEB_PASS; echo
  # strong secret for Flask session
  if command -v openssl >/dev/null 2>&1; then
    WEB_SECRET="$(openssl rand -hex 32)"
  else
    WEB_SECRET="$(python3 - <<'PY'\nimport secrets;print(secrets.token_hex(32))\nPY\n)"
  fi
  {
    echo "WEB_ADMIN_USER=${WEB_USER}"
    echo "WEB_ADMIN_PASSWORD=${WEB_PASS}"
    echo "WEB_SECRET=${WEB_SECRET}"
  } > "$ENVF"
  chmod 600 "$ENVF"
  say "${G}✅ Web login UI ဖွင့်ထားပါတယ်${Z}"
else
  rm -f "$ENVF" 2>/dev/null || true
  say "${Y}ℹ️ Web login UI မဖွင့်ထားပါ (dev mode)${Z}"
fi

# ===== Ask initial VPN passwords =====
say "${G}စောင့်နေရတာ{Z}"
read -r -p "Passwords (Enter=zi): " input_pw
if [ -ဇ "${input_pw:-}" ]; then PW_LIST='["zi"]'; else
  PW_LIST=$(echo "$input_pw" | awk -F',' '{
    printf("["); for(i=1;i<=NF;i++){gsub(/^ *| *$/,"",$i); printf("%s\"%s\"", (i>1?",":""), $i)}; printf("]")
  }')
fi

# ===== Update config.json =====
if jq . >/dev/null 2>&1 <<<'{}'; then
  TMP=$(mktemp)
  jq --argjson pw "$PW_LIST" '
    .auth.mode = "passwords" |
    .auth.config = $pw |
    .listen = (."listen" // ":5667") |
    .cert = "/etc/zivpn/zivpn.crt" |
    .key  = "/etc/zivpn/zivpn.key" |
    .obfs = (."obfs" // "zivpn")
  ' "$CFG" > "$TMP" && mv "$TMP" "$CFG"
fi
[ -f "$USERS" ] || echo "[]" > "$USERS"
chmod 644 "$CFG" "$USERS"

# ===== systemd: ZIVPN =====
say "${Y}အစRunပြီး..${Z}"
cat >/etc/systemd/system/zivpn.service <<'EOF'
[Unit]
Description=ZIVPN UDP Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn
ExecStart=/usr/local/bin/zivpn server -c /etc/zivpn/config.json
Restart=always
RestartSec=3
Environment=ZIVPN_LOG_LEVEL=info
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

# ===== Web Panel (Flask 1.x compatible, refresh 120s + Login UI) =====
say "${Y}ဖိုင်း ကို ထည့်နေပါတယ်...${Z}"
cat >/etc/zivpn/web.py <<'PY'
from flask import Flask, jsonify, render_template_string, request, redirect, url_for, session, make_response
import json, re, subprocess, os, tempfile, hmac
from datetime import datetime, timedelta

USERS_FILE = "/etc/zivpn/users.json"
CONFIG_FILE = "/etc/zivpn/config.json"
LISTEN_FALLBACK = "5667"
RECENT_SECONDS = 120

LOGO_URL = "https://raw.githubusercontent.com/KYAWSOEOO8/kso-script/main/icon.png"

# အပေါ်က code တွေအတိုင်းထားပြီး HTML အပိုင်းကိုပဲ အဓိက ပြင်ဆင်လိုက်ပါတယ်

HTML = """<!doctype html>
<html lang="my"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
<script src="https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js"></script>
<style>
    :root{ --bg:#f0f2f5; --fg:#1e293b; --primary:#2563eb; --ok:#10b981; --warn:#f59e0b; --bad:#ef4444; --card:#ffffff; --bd:#e2e8f0; --muted:#64748b; }
    *{box-sizing: border-box; font-family: 'Segoe UI', sans-serif; transition: all 0.2s ease;}
    body{ background:var(--bg); color:var(--fg); margin:0; padding:15px; display:flex; flex-direction:column; align-items:center; min-height:100vh; }
    header{ width:100%; max-width:400px; text-align:center; margin-bottom:15px; }
    .brand img{ width:70px; height:70px; border-radius:22px; border:3px solid #fff; box-shadow: 0 4px 15px rgba(0,0,0,0.1); margin-bottom:10px; }
    .brand h1{ font-size:1.5em; margin:0; font-weight:900; color:var(--primary); text-transform:uppercase; letter-spacing:1px; }
    .nav-links{ display:flex; gap:12px; justify-content:center; margin-bottom: 20px; }
    .nav-links a{ text-decoration:none; font-size:11px; font-weight:700; padding:10px 18px; border-radius:12px; background: #fff; box-shadow: 0 2px 5px rgba(0,0,0,0.05); color: var(--fg); border: 1px solid var(--bd); }
    form.box{ background:var(--card); border-radius:25px; padding:22px; width:100%; max-width:400px; margin-bottom:20px; box-shadow:0 10px 25px rgba(0,0,0,0.05); }
    .input-grp{ position:relative; margin-bottom: 15px; text-align: left; }
    .input-grp i{ position:absolute; left:12px; top:38px; color:var(--primary); font-size:14px; }
    label{ display:block; font-size:11px; color:var(--muted); margin-bottom:5px; font-weight:800; text-transform:uppercase; }
    input{ width:100%; padding:12px 12px 12px 38px; border:2px solid var(--bd); border-radius:12px; font-size:14px; background:#f8fafc; }
    .btn-primary{ background:var(--primary); color:#fff; border:none; width:100%; padding:15px; border-radius:15px; font-weight:800; cursor:pointer; display:flex; align-items:center; justify-content:center; gap:10px; }
    .table-container{ width:100%; max-width:400px; }
    table{ width:100%; border-collapse:separate; border-spacing: 0 10px; }
    td{ background:var(--card); padding:15px; box-shadow: 0 2px 8px rgba(0,0,0,0.03); position:relative; overflow:hidden; }
    td:first-child{ border-radius:18px 0 0 18px; text-align:left; padding-left:20px; }
    td:last-child{ border-radius:0 18px 18px 0; text-align:center; }
    .status-bar{ position:absolute; left:0; top:0; bottom:0; width:6px; }
    .bar-green{ background: var(--ok); } .bar-yellow{ background: var(--warn); } .bar-red{ background: var(--bad); }
    .action-group{ display:flex; gap:8px; justify-content:center; }
    .act-btn{ width:38px; height:38px; border-radius:10px; border:none; display:flex; align-items:center; justify-content:center; cursor:pointer; font-size:14px; }
    .btn-renew{ background:#e0f2fe; color:#0369a1; }
    .btn-del{ background:#fee2e2; color:var(--bad); }
    #receipt{ position: fixed; left: -9999px; width: 350px; background: #fff; padding: 30px; border-radius: 20px; text-align: center; }
</style></head><body>
{% if not authed %}
    {% else %}
    <header>
        <div class="brand"><img src="{{ logo }}"><h1>KSO VIP PANEL</h1></div>
        <div class="nav-links">
            <a href="https://m.me/kyawsoe.oo.1292019" target="_blank" style="color:#0084ff;"><i class="fa-brands fa-facebook-messenger"></i> SUPPORT</a>
            <a href="/logout" style="color:var(--bad);"><i class="fa-solid fa-power-off"></i> LOGOUT</a>
        </div>
    </header>

    <form method="post" action="/add" id="userForm" class="box">
        <div style="display:grid; grid-template-columns: 1fr 1fr; gap:15px;">
            <div class="input-grp"><label>နာမည်</label><i class="fa-solid fa-user-plus"></i><input id="inUser" name="user" required></div>
            <div class="input-grp"><label>စကားဝှက်</label><i class="fa-solid fa-key"></i><input id="inPass" name="password" required></div>
        </div>
        <div style="display:grid; grid-template-columns: 1fr 1fr; gap:15px;">
            <div class="input-grp"><label>ရက်ပေါင်း</label><i class="fa-solid fa-calendar-day"></i><input id="inDays" name="expires" placeholder="30"></div>
            <div class="input-grp"><label>UDP PORT</label><i class="fa-solid fa-bolt"></i><input name="port" placeholder="Auto"></div>
        </div>
        <button type="button" onclick="handleSave()" class="btn-primary">သိမ်းဆည်းမည် (SAVE) <i class="fa-solid fa-file-invoice"></i></button>
    </form>

    <div id="receipt">
        <div style="font-size:24px; font-weight:900; color:var(--primary); border-bottom:2px dashed #ddd; padding-bottom:10px; margin-bottom:15px;">KSO VIP</div>
        <div style="display:flex; justify-content:space-between; margin:8px 0;"><span>User:</span> <span id="rUser"></span></div>
        <div style="display:flex; justify-content:space-between; margin:8px 0;"><span>Pass:</span> <span id="rPass"></span></div>
        <div style="display:flex; justify-content:space-between; margin:8px 0;"><span>Exp:</span> <span id="rDate"></span></div>
        <div style="margin-top:15px; color:var(--ok); font-weight:bold;">Thank You!</div>
    </div>

    <div class="table-container">
        <table>
            <tbody>
                {% for u in users %}
                <tr>
                    <td>
                        {% set d = u.days_left | default(0) | int %}
                        <div class="status-bar {% if d > 10 %}bar-green{% elif d > 3 %}bar-yellow{% else %}bar-red{% endif %}"></div>
                        <strong>{{u.user}}</strong><br>
                        <small style="color:var(--muted);"><i class="fa-solid fa-clock"></i> {{u.expires}} ({{d}} ရက်ကျန်)</small>
                    </td>
                    <td>
                        <div class="action-group">
                            <button type="button" class="act-btn btn-renew" onclick="prepareRenew('{{u.user}}', '{{u.password}}')" title="Renew User">
                                <i class="fa-solid fa-arrows-rotate"></i>
                            </button>
                            <form method="post" action="/delete" onsubmit="return confirm('ဖျက်မှာသေချာလား?')" style="margin:0;">
                                <input type="hidden" name="user" value="{{u.user}}">
                                <button type="submit" class="act-btn btn-del"><i class="fa-solid fa-trash-can"></i></button>
                            </form>
                        </div>
                    </td>
                </tr>
                {% endfor %}
            </tbody>
        </table>
    </div>

    <script>
    function prepareRenew(u, p) {
        document.getElementById('inUser').value = u;
        document.getElementById('inPass').value = p;
        document.getElementById('inDays').value = ""; // ရက်အသစ်ရိုက်ရန် နေရာလွတ်ပေးထားမည်
        document.getElementById('inDays').focus(); // ရက်ပေါင်းရိုက်တဲ့နေရာကို auto pointer ချပေးမည်
        window.scrollTo({top: 0, behavior: 'smooth'}); // အပေါ်ဆုံးကို ဖြည်းဖြည်းချင်း ပြန်တက်သွားမည်
    }

    function handleSave() {
        const user = document.getElementById('inUser').value;
        const pass = document.getElementById('inPass').value;
        const days = document.getElementById('inDays').value || "30";
        if(!user || !pass) { alert("အချက်အလက်ဖြည့်ပါ"); return; }
        
        document.getElementById('rUser').innerText = user;
        document.getElementById('rPass').innerText = pass;
        const d = new Date();
        d.setDate(d.getDate() + parseInt(days));
        document.getElementById('rDate').innerText = d.toISOString().split('T')[0];

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
</body></html>
"""
app = Flask(__name__)

# Secret & Admin credentials (via env)
app.secret_key = os.environ.get("WEB_SECRET","dev-secret-change-me")
ADMIN_USER = os.environ.get("WEB_ADMIN_USER","").strip()
ADMIN_PASS = os.environ.get("WEB_ADMIN_PASSWORD","").strip()

def read_json(path, default):
  try:
    with open(path,"r") as f: return json.load(f)
  except Exception:
    return default

def write_json_atomic(path, data):
  d=json.dumps(data, ensure_ascii=False, indent=2)
  dirn=os.path.dirname(path); fd,tmp=tempfile.mkstemp(prefix=".tmp-", dir=dirn)
  try:
    with os.fdopen(fd,"w") as f: f.write(d)
    os.replace(tmp,path)
  finally:
    try: os.remove(tmp)
    except: pass

def load_users():
  v=read_json(USERS_FILE,[])
  out=[]
  for u in v:
    out.append({"user":u.get("user",""),
                "password":u.get("password",""),
                "expires":u.get("expires",""),
                "port":str(u.get("port","")) if u.get("port","")!="" else ""})
  return out

def save_users(users): write_json_atomic(USERS_FILE, users)

def get_listen_port_from_config():
  cfg=read_json(CONFIG_FILE,{})
  listen=str(cfg.get("listen","")).strip()
  import re as _re
  m=_re.search(r":(\d+)$", listen) if listen else None
  return (m.group(1) if m else LISTEN_FALLBACK)

def get_udp_listen_ports():
  out=subprocess.run("ss -uHln", shell=True, capture_output=True, text=True).stdout
  import re as _re
  return set(_re.findall(r":(\d+)\s", out))

def pick_free_port():
  used={str(u.get("port","")) for u in load_users() if str(u.get("port",""))}
  used |= get_udp_listen_ports()
  for p in range(6000,20000):
    if str(p) not in used: return str(p)
  return ""

def has_recent_udp_activity(port):
  if not port: return False
  try:
    out=subprocess.run("conntrack -L -p udp 2>/dev/null | grep 'dport=%s\\b'"%port,
                       shell=True, capture_output=True, text=True).stdout
    return bool(out)
  except Exception:
    return False

def status_for_user(u, active_ports, listen_port):
  port=str(u.get("port",""))
  check_port=port if port else listen_port
  if has_recent_udp_activity(check_port): return "Online"
  if check_port in active_ports: return "Offline"
  return "Unknown"

# --- mirror sync: config.json(auth.config) = users.json passwords only
def sync_config_passwords(mode="mirror"):
  cfg=read_json(CONFIG_FILE,{})
  users=load_users()
  users_pw=sorted({str(u["password"]) for u in users if u.get("password")})
  if mode=="merge":
    old=[]
    if isinstance(cfg.get("auth",{}).get("config",None), list):
      old=list(map(str, cfg["auth"]["config"]))
    new_pw=sorted(set(old)|set(users_pw))
  else:
    new_pw=users_pw
  if not isinstance(cfg.get("auth"),dict): cfg["auth"]={}
  cfg["auth"]["mode"]="passwords"
  cfg["auth"]["config"]=new_pw
  cfg["listen"]=cfg.get("listen") or ":5667"
  cfg["cert"]=cfg.get("cert") or "/etc/zivpn/zivpn.crt"
  cfg["key"]=cfg.get("key") or "/etc/zivpn/zivpn.key"
  cfg["obfs"]=cfg.get("obfs") or "zivpn"
  write_json_atomic(CONFIG_FILE,cfg)
  subprocess.run("systemctl restart zivpn.service", shell=True)

# --- Login guard helpers
def login_enabled(): return bool(ADMIN_USER and ADMIN_PASS)
def is_authed(): return session.get("auth") == True
def require_login():
  if login_enabled() and not is_authed():
    return False
  return True

def build_view(msg="", err=""):
  if not require_login():
    # render login UI
    return render_template_string(HTML, authed=False, logo=LOGO_URL, err=session.pop("login_err", None))
  users=load_users()
  active=get_udp_listen_ports()
  listen_port=get_listen_port_from_config()
  view=[]
  for u in users:
    view.append(type("U",(),{
      "user":u.get("user",""),
      "password":u.get("password",""),
      "expires":u.get("expires",""),
      "port":u.get("port",""),
      "status":status_for_user(u,active,listen_port)
    }))
  view.sort(key=lambda x:(x.user or "").lower())
  today=datetime.now().strftime("%Y-%m-%d")
  return render_template_string(HTML, authed=True, logo=LOGO_URL, users=view, msg=msg, err=err, today=today)

@app.route("/login", methods=["GET","POST"])
def login():
  if not login_enabled():
    return redirect(url_for('index'))
  if request.method=="POST":
    u=(request.form.get("u") or "").strip()
    p=(request.form.get("p") or "").strip()
    if hmac.compare_digest(u, ADMIN_USER) and hmac.compare_digest(p, ADMIN_PASS):
      session["auth"]=True
      return redirect(url_for('index'))
    else:
      session["auth"]=False
      session["login_err"]="မှန်ကန်မှုမရှိပါ (username/password)"
      return redirect(url_for('login'))
  # GET
  return render_template_string(HTML, authed=False, logo=LOGO_URL, err=session.pop("login_err", None))

@app.route("/logout", methods=["GET"])
def logout():
  session.pop("auth", None)
  return redirect(url_for('login') if login_enabled() else url_for('index'))

@app.route("/", methods=["GET"])
def index(): return build_view()

@app.route("/add", methods=["POST"])
def add_user():
  if not require_login(): return redirect(url_for('login'))
  user=(request.form.get("user") or "").strip()
  password=(request.form.get("password") or "").strip()
  expires=(request.form.get("expires") or "").strip()
  port=(request.form.get("port") or "").strip()

  if expires.isdigit():
    expires=(datetime.now() + timedelta(days=int(expires))).strftime("%Y-%m-%d")

  if not user or not password:
    return build_view(err="User နှင့် Password လိုအပ်သည်")
  try:
    if expires:
      datetime.strptime(expires,"%Y-%m-%d")
  except ValueError:
    return build_view(err="Expires format မမှန်ပါ (YYYY-MM-DD)")
  if port:
    import re as _re
    if not _re.fullmatch(r"\d{2,5}",port) or not (6000 <= int(port) <= 19999):
      return build_view(err="Port အကွာအဝေး 6000-19999")
  else:
    port=pick_free_port()

  users=load_users(); replaced=False
  for u in users:
    if u.get("user","").lower()==user.lower():
      u["password"]=password; u["expires"]=expires; u["port"]=port; replaced=True; break
  if not replaced:
    users.append({"user":user,"password":password,"expires":expires,"port":port})
  save_users(users); sync_config_passwords()
  return build_view(msg="Saved & Synced")

@app.route("/delete", methods=["POST"])
def delete_user_html():
  if not require_login(): return redirect(url_for('login'))
  user = (request.form.get("user") or "").strip()
  if not user:
    return build_view(err="User လိုအပ်သည်")
  remain = [u for u in load_users() if (u.get("user","").lower() != user.lower())]
  save_users(remain)
  sync_config_passwords(mode="mirror")
  return build_view(msg=f"Deleted: {user}")

@app.route("/api/user.delete", methods=["POST"])
def delete_user_api():
  if not require_login():
    return make_response(jsonify({"ok": False, "err":"login required"}), 401)
  data = request.get_json(silent=True) or {}
  user = (data.get("user") or "").strip()
  if not user:
    return jsonify({"ok": False, "err": "user required"}), 400
  remain = [u for u in load_users() if (u.get("user","").lower() != user.lower())]
  save_users(remain)
  sync_config_passwords(mode="mirror")
  return jsonify({"ok": True})

@app.route("/api/users", methods=["GET","POST"])
def api_users():
  if not require_login():
    return make_response(jsonify({"ok": False, "err":"login required"}), 401)
  if request.method=="GET":
    users=load_users(); active=get_udp_listen_ports(); listen_port=get_listen_port_from_config()
    for u in users: u["status"]=status_for_user(u,active,listen_port)
    return jsonify(users)
  data=request.get_json(silent=True) or {}
  user=(data.get("user") or "").strip()
  password=(data.get("password") or "").strip()
  expires=(data.get("expires") or "").strip()
  port=str(data.get("port") or "").strip()
  if expires.isdigit():
    expires=(datetime.now()+timedelta(days=int(expires))).strftime("%Y-%m-%d")
  if not user or not password: return jsonify({"ok":False,"err":"user/password required"}),400
  import re as _re
  if port and (not _re.fullmatch(r"\d{2,5}",port) or not (6000<=int(port)<=19999)):
    return jsonify({"ok":False,"err":"invalid port"}),400
  if not port: port=pick_free_port()
  users=load_users(); replaced=False
  for u in users:
    if u.get("user","").lower()==user.lower():
      u["password"]=password; u["expires"]=expires; u["port"]=port; replaced=True; break
  if not replaced:
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
echo -e "${Y}စောင့်ပိုတွေ...${Z}"
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
echo -e "\n$LINE\n${G}🕳💣💣💣${Z}"
echo -e "${C}Web Panel   :${Z} ${Y}http://$IP:8880${Z}"
echo -e "${C}users.json  :${Z} ${Y}/etc/zivpn/users.json${Z}"
echo -e "${C}config.json :${Z} ${Y}/etc/zivpn/config.json${Z}"
echo -e "${C}Services    :${Z} ${Y}systemctl status|restart zivpn  •  systemctl status|restart zivpn-web${Z}"
echo -ે "$LINE"  say "${Y}အသုံးပြုနိုင်ပြီး မသာလေး...${Z}"
  openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
    -subj "/C=MM/ST=Yangon/L=Yangon/O=UPK/OU=Net/CN=zivpn" \
    -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt" >/dev/null 2>&1
fi

# ===== Web Admin (Login UI credentials) =====
say "${Y}🔒 Web Admin Login UI ထည့်မလား? (လစ်: မဖိတ်)${Z}"
read -r -p "Web Admin Username (Enter=disable): " WEB_USER
if [ -n "${WEB_USER:-}" ]; then
  read -r -s -p "Web Admin Password: " WEB_PASS; echo
  # strong secret for Flask session
  if command -v openssl >/dev/null 2>&1; then
    WEB_SECRET="$(openssl rand -hex 32)"
  else
    WEB_SECRET="$(python3 - <<'PY'\nimport secrets;print(secrets.token_hex(32))\nPY\n)"
  fi
  {
    echo "WEB_ADMIN_USER=${WEB_USER}"
    echo "WEB_ADMIN_PASSWORD=${WEB_PASS}"
    echo "WEB_SECRET=${WEB_SECRET}"
  } > "$ENVF"
  chmod 600 "$ENVF"
  say "${G}✅ Web login UI ဖွင့်ထားပါတယ်${Z}"
else
  rm -f "$ENVF" 2>/dev/null || true
  say "${Y}ℹ️ Web login UI မဖွင့်ထားပါ (dev mode)${Z}"
fi

# ===== Ask initial VPN passwords =====
say "${G}🔏 KSO-VIP{Z}"
read -r -p "Passwords (Enter=zi): " input_pw
if [ -z "${input_pw:-}" ]; then PW_LIST='["zi"]'; else
  PW_LIST=$(echo "$input_pw" | awk -F',' '{
    printf("["); for(i=1;i<=NF;i++){gsub(/^ *| *$/,"",$i); printf("%s\"%s\"", (i>1?",":""), $i)}; printf("]")
  }')
fi

# ===== Update config.json =====
if jq . >/dev/null 2>&1 <<<'{}'; then
  TMP=$(mktemp)
  jq --argjson pw "$PW_LIST" '
    .auth.mode = "passwords" |
    .auth.config = $pw |
    .listen = (."listen" // ":5667") |
    .cert = "/etc/zivpn/zivpn.crt" |
    .key  = "/etc/zivpn/zivpn.key" |
    .obfs = (."obfs" // "zivpn")
  ' "$CFG" > "$TMP" && mv "$TMP" "$CFG"
fi
[ -f "$USERS" ] || echo "[]" > "$USERS"
chmod 644 "$CFG" "$USERS"

# ===== systemd: ZIVPN =====
say "${Y}🖕🏻🖕🏻🖕🏻 ခဏစောင့်ဦးဘဲကြီး(zivpn) ကို သွင်းနေပါတယ်...${Z}"
cat >/etc/systemd/system/zivpn.service <<'EOF'
[Unit]
Description=ZIVPN UDP Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn
ExecStart=/usr/local/bin/zivpn server -c /etc/zivpn/config.json
Restart=always
RestartSec=3
Environment=ZIVPN_LOG_LEVEL=info
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

# ===== Web Panel (Flask 1.x compatible, refresh 120s + Login UI) =====
say "${Y}🤡🤡🤡 ရတော့မယ်...${Z}"
cat >/etc/zivpn/web.py <<'PY'
from flask import Flask, jsonify, render_template_string, request, redirect, url_for, session, make_response
import json, re, subprocess, os, tempfile, hmac
from datetime import datetime, timedelta

USERS_FILE = "/etc/zivpn/users.json"
CONFIG_FILE = "/etc/zivpn/config.json"
LISTEN_FALLBACK = "5667"
RECENT_SECONDS = 120

LOGO_URL = "https://raw.githubusercontent.com/KYAWSOEOO8/kso-script/main/icon.png"


HTML = """<!doctype html>
<html lang="my"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="refresh" content="120">
<style>
 :root{
  --bg:#ffffff; --fg:#111; --muted:#666; --card:#fafafa; --bd:#e5e5e5;
  --ok:#0a8a0a; --bad:#c0392b; --unk:#666; --btn:#fff; --btnbd:#ccc;
  --pill:#f5f5f5; --pill-bad:#ffecec; --pill-ok:#eaffe6; --pill-unk:#f0f0f0;
 }
 html,body{background:var(--bg);color:var(--fg); min-height: 100vh;}
 body{
   font-family:system-ui,Segoe UI,Roboto,Arial;
   margin:0; 
   display:flex; 
   flex-direction:column; 
   align-items:center; 
   padding:24px;
   box-sizing: border-box;
 }
 header{display:flex;flex-direction:column;align-items:center;gap:14px;margin-bottom:24px;text-align:center}
 h1{margin:0;font-size:1.8em;font-weight:600;line-height:1.2}
 .sub{color:var(--muted);font-size:.95em}
 .btn{
   padding:8px 14px;border-radius:999px;border:1px solid var(--btnbd);
   background:var(--btn);color:var(--fg);text-decoration:none;white-space:nowrap;cursor:pointer;
   display: inline-block;
 }
 table{border-collapse:collapse;width:100%;max-width:400px;margin: 0 auto}
 th,td{border:1px solid var(--bd);padding:10px;text-align:center} /* စာသားတွေကိုပါ အလယ်ပို့ထားပါတယ် */
 th{background:var(--card)}
 .ok{color:var(--ok);background:var(--pill-ok)}
 .bad{color:var(--bad);background:var(--pill-bad)}
 .unk{color:var(--unk);background:var(--pill-unk)}
 .pill{display:inline-block;padding:4px 10px;border-radius:999px}
 form.box{margin:18px auto;padding:24px;border:1px solid var(--bd);border-radius:12px;background:var(--card);max-width:480px;width:100%;text-align:left}
 label{display:block;margin:6px 0 2px}
 input{width:100%;padding:9px 12px;border:1px solid var(--bd);border-radius:10px;box-sizing:border-box}
 .row{display:flex;gap:18px;flex-wrap:wrap;justify-content:center}
 .row>div{flex:1 1 220px}
 .msg{margin:10px 0;color:var(--ok);text-align:center}
 .err{margin:10px 0;color:var(--bad);text-align:center}
 .muted{color:var(--muted)}
 .delform{display:inline}
 tr.expired td{opacity:.9; text-decoration-color: var(--bad);}
 .center{display:flex;align-items:center;justify-content:center;text-align:center}
 .login-card{max-width:420px;width:100%;margin:auto;padding:24px;border:1px solid var(--bd);border-radius:14px;background:var(--card)}
 .login-card h3{margin:10px 0 6px}
 .logo{height:64px;width:auto;border-radius:14px;box-shadow:0 2px 6px rgba(0,0,0,0.15)}
</style></head><body>

{% if not authed %}
  <div class="login-card">
    <div class="center"><img class="logo" src="{{ logo }}" alt="KSO-VIP"></div>
    <h3 class="center">KSO-VIP</h3>
    {% if err %}<div class="err">{{err}}</div>{% endif %}
    <form method="post" action="/login">
      <label>Username</label>
      <input name="u" autofocus required>
      <label style="margin-top:8px">Password</label>
      <input name="p" type="password" required>
      <button class="btn" type="submit" style="margin-top:20px;width:100%; background:#111; color:#fff">Login</button>
    </form>
  </div>
{% else %}
<header>
  <div class="logo-container">
    <img src="{{ logo }}" alt="KSO-VIP" style="width: 80px; height: 80px; border-radius: 50%; box-shadow: 0 4px 8px rgba(0,0,0,0.1);">
  </div>
  <div>
    <h1>KSO VIP</h1>
  </div>
  <div style="width: 100%; max-width: 90px;">
    <a class="btn" href="https://m.me/kyawsoe.oo.1292019" target="_blank" rel="noopener" 
       style="display: block; background: #0084ff; color: white; border: none; padding: 12px; font-weight: bold; text-decoration: none; border-radius: 8px;">
      💬 Contact (Messenger)
    </a>
    <a class="btn" href="/logout">Logout</a>
  </div>
</header>

<form method="post" action="/add" class="box">
HTML = """<!doctype html>
<html lang="my"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<style>
 :root{
  --bg:#f8fafc; --fg:#0f172a; --muted:#64748b; --card:#ffffff; --bd:#e2e8f0;
  --primary:#2563eb; --ok:#10b981; --bad:#ef4444; --warn:#f59e0b;
 }
 *{box-sizing: border-box; font-family: system-ui, sans-serif;}
 body{ background:var(--bg); color:var(--fg); margin:0; padding:10px; display:flex; flex-direction:column; align-items:center; }
 
 /* Header Centralized */
 header{ width:100%; max-width:400px; text-align:center; margin-bottom:15px; }
 .brand img{ width:55px; height:55px; border-radius:12px; margin-bottom:5px; }
 .brand h1{ font-size:1.2em; margin:0; font-weight:800; color:var(--primary); text-transform:uppercase; }

 /* Box Input */
 form.box{ background:var(--card); border:1px solid var(--bd); border-radius:12px; padding:15px; width:100%; max-width:400px; margin-bottom:15px; box-shadow:0 2px 4px rgba(0,0,0,0.05); }
 .row{ display:grid; grid-template-columns: 1fr 1fr; gap:10px; margin-bottom:10px; }
 label{ display:block; font-size:10px; color:var(--muted); margin-bottom:3px; font-weight:700; text-align:left; }
 input{ width:100%; padding:8px; border:1px solid var(--bd); border-radius:6px; font-size:14px; background:#fcfcfc; }
 .btn-p{ background:var(--primary); color:#fff; border:none; width:100%; padding:10px; border-radius:8px; font-weight:700; cursor:pointer; margin-top:5px; }

 /* Compact Table */
 .table-container{ width:100%; max-width:400px; }
HTML = """<!doctype html>
<html lang="my"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
<script src="https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js"></script>
<style>
 :root{
  --bg:#f0f2f5; --fg:#1e293b; --primary:#2563eb; --ok:#10b981; --warn:#f59e0b; --bad:#ef4444; --card:#ffffff; --bd:#e2e8f0; --muted:#64748b;
 }
 *{box-sizing: border-box; font-family: 'Segoe UI', sans-serif; transition: all 0.2s ease;}
 body{ background:var(--bg); color:var(--fg); margin:0; padding:15px; display:flex; flex-direction:column; align-items:center; min-height:100vh; }
 
 /* Header Section */
 header{ width:100%; max-width:400px; text-align:center; margin-bottom:15px; }
 .brand img{ width:70px; height:70px; border-radius:22px; border:3px solid #fff; box-shadow: 0 4px 15px rgba(0,0,0,0.1); margin-bottom:10px; }
 .brand h1{ font-size:1.5em; margin:0; font-weight:900; color:var(--primary); text-transform:uppercase; letter-spacing:1px; }

 /* Login UI */
 .login-card{ margin-top:50px; background:#fff; padding:35px; border-radius:30px; width:100%; max-width:360px; text-align:center; box-shadow:0 20px 40px rgba(0,0,0,0.1); border: 1px solid var(--bd); }
 .login-card h2{ margin:0 0 25px; font-weight:900; color:var(--fg); font-size: 1.3em; }

 /* Shared Form Elements */
 .input-grp{ position:relative; margin-bottom: 15px; text-align: left; }
 .input-grp i{ position:absolute; left:12px; top:38px; color:var(--primary); font-size:14px; }
 label{ display:block; font-size:11px; color:var(--muted); margin-bottom:5px; font-weight:800; text-transform:uppercase; padding-left: 5px; }
 input{ width:100%; padding:12px 12px 12px 38px; border:2px solid var(--bd); border-radius:12px; font-size:14px; background:#f8fafc; width: 100%; }
 input:focus{ border-color:var(--primary); background:#fff; outline:none; box-shadow: 0 0 0 4px var(--primary-light); }

 .btn-primary{ background:var(--primary); color:#fff; border:none; width:100%; padding:15px; border-radius:15px; font-weight:800; cursor:pointer; display:flex; align-items:center; justify-content:center; gap:10px; font-size:14px; box-shadow: 0 4px 12px rgba(37, 99, 235, 0.2); }

 /* Dashboard Items */
 .nav-links{ display:flex; gap:12px; justify-content:center; margin: 10px 0 20px; }
 .nav-links a{ text-decoration:none; font-size:11px; font-weight:700; padding:10px 18px; border-radius:12px; background: #fff; box-shadow: 0 2px 5px rgba(0,0,0,0.05); color: var(--fg); border: 1px solid var(--bd); }

 form.box{ background:var(--card); border-radius:25px; padding:22px; width:100%; max-width:400px; margin-bottom:20px; box-shadow:0 10px 25px rgba(0,0,0,0.05); }
 .row{ display:grid; grid-template-columns: 1fr 1fr; gap:15px; }

 /* Receipt Design */
 #receipt{ position: fixed; left: -9999px; width: 350px; background: #fff; padding: 35px; border-radius: 25px; text-align: center; }
 .r-title{ color: var(--primary); font-size: 28px; font-weight: 900; border-bottom: 3px dashed var(--bd); padding-bottom: 15px; margin-bottom: 20px; }
 .r-row{ display: flex; justify-content: space-between; margin-bottom: 12px; font-size: 16px; font-weight: 600; color: #334155; }
 .r-foot{ margin-top: 20px; padding-top: 15px; border-top: 1px solid #eee; color: var(--ok); font-weight: 800; font-size: 16px; }

 /* User Table */
 .table-container{ width:100%; max-width:400px; }
 table{ width:100%; border-collapse:separate; border-spacing: 0 10px; }
 td{ background:var(--card); padding:15px; box-shadow: 0 2px 8px rgba(0,0,0,0.03); position:relative; overflow:hidden; }
 td:first-child{ border-radius:18px 0 0 18px; text-align:left; padding-left:20px; }
 td:last-child{ border-radius:0 18px 18px 0; text-align:center; }
 
 .status-bar{ position:absolute; left:0; top:0; bottom:0; width:6px; }
 .bar-green{ background: var(--ok); } .bar-yellow{ background: var(--warn); } .bar-red{ background: var(--bad); }

 .action-group{ display:flex; gap:10px; justify-content:center; }
 .act-btn{ width:42px; height:42px; border-radius:12px; border:none; display:flex; align-items:center; justify-content:center; cursor:pointer; position:relative; font-size: 18px; }
 .btn-cal{ background:#dbeafe; color:var(--primary); } 
 .btn-del{ background:#fee2e2; color:var(--bad); }
 .input-cal{ position:absolute; opacity:0; width:100%; height:100%; cursor:pointer; }
</style></head><body>

{% if not authed %}
  <div class="login-card">
    <img src="{{ logo }}" style="width:85px; height:85px; border-radius:22px; margin-bottom:15px; border: 3px solid var(--primary-light);">
    <h2>ADMIN ACCESS</h2>
    <form method="post" action="/login">
        <div class="input-grp">
            <label>Username</label>
            <i class="fa-solid fa-circle-user"></i>
            <input name="u" placeholder="Admin Name" required autofocus>
        </div>
        <div class="input-grp">
            <label>Password</label>
            <i class="fa-solid fa-shield-halved"></i>
            <input name="p" type="password" placeholder="••••••••" required>
        </div>
        <button class="btn-primary" style="margin-top:20px;">
            SIGN IN <i class="fa-solid fa-arrow-right-to-bracket"></i>
        </button>
    </form>
  </div>

{% else %}
  <header>
    <div class="brand"><img src="{{ logo }}"><h1>KSO VIP PANEL</h1></div>
    <div class="nav-links">
      <a href="https://m.me/kyawsoe.oo.1292019" target="_blank" style="color:#0084ff;"><i class="fa-brands fa-facebook-messenger"></i> SUPPORT</a>
      <a href="/logout" style="color:var(--bad);"><i class="fa-solid fa-power-off"></i> LOGOUT</a>
    </div>
  </header>

  <form method="post" action="/add" id="userForm" class="box">
    <div class="row">
      <div class="input-grp"><label>နာမည်</label><i class="fa-solid fa-user-plus"></i><input id="inUser" name="user" required></div>
      <div class="input-grp"><label>စကားဝှက်</label><i class="fa-solid fa-key"></i><input id="inPass" name="password" required></div>
    </div>
    <div class="row">
      <div class="input-grp"><label>ရက်ပေါင်း</label><i class="fa-solid fa-calendar-day"></i><input id="inDays" name="expires" placeholder="30"></div>
      <div class="input-grp"><label>UDP PORT</label><i class="fa-solid fa-bolt"></i><input name="port" placeholder="Auto"></div>
    </div>
    <button type="button" onclick="handleSave()" class="btn-primary">
        SAVE & SYNC DATA <i class="fa-solid fa-file-invoice"></i>
    </button>
  </form>

  <div id="receipt">
      <div class="r-title">KSO VIP</div>
      <div class="r-row"><span>နာမည်:</span> <span id="rUser"></span></div>
      <div class="r-row"><span>စကားဝှက်:</span> <span id="rPass"></span></div>
      <div class="r-row"><span>ကုန်ရက်:</span> <span id="rDate"></span></div>
      <div class="r-foot">ကျေးဇူးတင်ပါသည်</div>
  </div>

  <div class="table-container">
    <table>
      <tbody>
        {% for u in users %}
        <tr>
          <td>
            {% set d = u.days_left | int %}
            <div class="status-bar {% if d > 10 %}bar-green{% elif d > 3 %}bar-yellow{% else %}bar-red{% endif %}"></div>
            <strong style="font-size:15px;">{{u.user}}</strong><br>
            <small style="color:var(--muted); font-weight:600;"><i class="fa-solid fa-clock"></i> {{u.expires}} ({{d}}d left)</small>
          </td>
          <td>
            <div class="action-group">
              <form method="post" action="/add" style="margin:0;">
                  <input type="hidden" name="user" value="{{u.user}}"><input type="hidden" name="mode" value="set">
             <div class="act-btn btn-cal"><i class="fa-solid fa-calendar-check"></i>
    <input type="date" name="expires" class="input-cal" onchange="this.form.submit()">
</div>

              </form>
              <form method="post" action="/delete" onsubmit="return confirm('ဖျက်မှာ သေချာပါသလား?')" style="margin:0;"><input type="hidden" name="user" value="{{u.user}}">
                  <button type="submit" class="act-btn btn-del"><i class="fa-solid fa-trash-can"></i></button>
              </form>
            </div>
          </td>
        </tr>
        {% endfor %}
      </tbody>
    </table>
  </div>

  <script>
  function handleSave() {
      const user = document.getElementById('inUser').value;
      const pass = document.getElementById('inPass').value;
      const days = document.getElementById('inDays').value || "30";
      if(!user || !pass) { alert("အချက်အလက်ပြည့်စုံစွာဖြည့်ပါ"); return; }

      document.getElementById('rUser').innerText = user;
      document.getElementById('rPass').innerText = pass;
      const d = new Date(); d.setDate(d.getDate() + parseInt(days));
      document.getElementById('rDate').innerText = d.toISOString().split('T')[0];

      html2canvas(document.getElementById('receipt'), {scale: 2}).then(canvas => {
          const link = document.createElement('a');
          link.download = 'KSO_VIP_' + user + '.png';
          link.href = canvas.toDataURL("image/png");
          link.click();
          document.getElementById('userForm').submit();
      });
  }
  </script>
{% endif %}
</body></html>"""



app = Flask(__name__)

# Secret & Admin credentials (via env)
app.secret_key = os.environ.get("WEB_SECRET","dev-secret-change-me")
ADMIN_USER = os.environ.get("WEB_ADMIN_USER","").strip()
ADMIN_PASS = os.environ.get("WEB_ADMIN_PASSWORD","").strip()

def read_json(path, default):
  try:
    with open(path,"r") as f: return json.load(f)
  except Exception:
    return default

def write_json_atomic(path, data):
  d=json.dumps(data, ensure_ascii=False, indent=2)
  dirn=os.path.dirname(path); fd,tmp=tempfile.mkstemp(prefix=".tmp-", dir=dirn)
  try:
    with os.fdopen(fd,"w") as f: f.write(d)
    os.replace(tmp,path)
  finally:
    try: os.remove(tmp)
    except: pass

def load_users():
  v=read_json(USERS_FILE,[])
  out=[]
  for u in v:
    out.append({"user":u.get("user",""),
                "password":u.get("password",""),
                "expires":u.get("expires",""),
                "port":str(u.get("port","")) if u.get("port","")!="" else ""})
  return out

def save_users(users): write_json_atomic(USERS_FILE, users)

def get_listen_port_from_config():
  cfg=read_json(CONFIG_FILE,{})
  listen=str(cfg.get("listen","")).strip()
  m=re.search(r":(\d+)$", listen) if listen else None
  return (m.group(1) if m else LISTEN_FALLBACK)

def get_udp_listen_ports():
  out=subprocess.run("ss -uHln", shell=True, capture_output=True, text=True).stdout
  return set(re.findall(r":(\d+)\s", out))

def pick_free_port():
  used={str(u.get("port","")) for u in load_users() if str(u.get("port",""))}
  used |= get_udp_listen_ports()
  for p in range(6000,20000):
    if str(p) not in used: return str(p)
  return ""

def has_recent_udp_activity(port):
  if not port: return False
  try:
    out=subprocess.run("conntrack -L -p udp 2>/dev/null | grep 'dport=%s\\b'"%port,
                       shell=True, capture_output=True, text=True).stdout
    return bool(out)
  except Exception:
    return False

def status_for_user(u, active_ports, listen_port):
  port=str(u.get("port",""))
  check_port=port if port else listen_port
  if has_recent_udp_activity(check_port): return "Online"
  if check_port in active_ports: return "Offline"
  return "Unknown"

# --- mirror sync: config.json(auth.config) = users.json passwords only
def sync_config_passwords(mode="mirror"):
  cfg=read_json(CONFIG_FILE,{})
  users=load_users()
  users_pw=sorted({str(u["password"]) for u in users if u.get("password")})
  if mode=="merge":
    old=[]
    if isinstance(cfg.get("auth",{}).get("config",None), list):
      old=list(map(str, cfg["auth"]["config"]))
    new_pw=sorted(set(old)|set(users_pw))
  else:
    new_pw=users_pw
  if not isinstance(cfg.get("auth"),dict): cfg["auth"]={}
  cfg["auth"]["mode"]="passwords"
  cfg["auth"]["config"]=new_pw
  cfg["listen"]=cfg.get("listen") or ":5667"
  cfg["cert"]=cfg.get("cert") or "/etc/zivpn/zivpn.crt"
  cfg["key"]=cfg.get("key") or "/etc/zivpn/zivpn.key"
  cfg["obfs"]=cfg.get("obfs") or "zivpn"
  write_json_atomic(CONFIG_FILE,cfg)
  subprocess.run("systemctl restart zivpn.service", shell=True)

# --- Login guard helpers
def login_enabled(): return bool(ADMIN_USER and ADMIN_PASS)
def is_authed(): return session.get("auth") == True
def require_login():
  if login_enabled() and not is_authed():
    return False
  return True

def build_view(msg="", err=""):
  if not require_login():
    # render login UI
    return render_template_string(HTML, authed=False, logo=LOGO_URL, err=session.pop("login_err", None))
  users=load_users()
  active=get_udp_listen_ports()
  listen_port=get_listen_port_from_config()
  view=[]
  for u in users:
    view.append(type("U",(),{
      "user":u.get("user",""),
      "password":u.get("password",""),
      "expires":u.get("expires",""),
      "port":u.get("port",""),
      "status":status_for_user(u,active,listen_port)
    }))
  view.sort(key=lambda x:(x.user or "").lower())
  today=datetime.now().strftime("%Y-%m-%d")
  return render_template_string(HTML, authed=True, logo=LOGO_URL, users=view, msg=msg, err=err, today=today)

@app.route("/login", methods=["GET","POST"])
def login():
  if not login_enabled():
    return redirect(url_for('index'))
  if request.method=="POST":
    u=(request.form.get("u") or "").strip()
    p=(request.form.get("p") or "").strip()
    if hmac.compare_digest(u, ADMIN_USER) and hmac.compare_digest(p, ADMIN_PASS):
      session["auth"]=True
      return redirect(url_for('index'))
    else:
      session["auth"]=False
      session["login_err"]="မှန်ကန်မှုမရှိပါ (username/password)"
      return redirect(url_for('login'))
  # GET
  return render_template_string(HTML, authed=False, logo=LOGO_URL, err=session.pop("login_err", None))

@app.route("/logout", methods=["GET"])
def logout():
  session.pop("auth", None)
  return redirect(url_for('login') if login_enabled() else url_for('index'))

@app.route("/", methods=["GET"])
def index(): return build_view()

@app.route("/add", methods=["POST"])
def add_user():
  if not require_login(): return redirect(url_for('login'))
  user=(request.form.get("user") or "").strip()
  password=(request.form.get("password") or "").strip()
  expires=(request.form.get("expires") or "").strip()
  port=(request.form.get("port") or "").strip()

  if expires.isdigit():
    expires=(datetime.now() + timedelta(days=int(expires))).strftime("%Y-%m-%d")

  if not user or not password:
    return build_view(err="User နှင့် Password လိုအပ်သည်")
  if expires:
    try: datetime.strptime(expires,"%Y-%m-%d")
    except ValueError:
      return build_view(err="Expires format မမှန်ပါ (YYYY-MM-DD)")
  if port:
    if not re.fullmatch(r"\d{2,5}",port) or not (6000 <= int(port) <= 19999):
      return build_view(err="Port အကွာအဝေး 6000-19999")
  else:
    port=pick_free_port()

  users=load_users(); replaced=False
  for u in users:
    if u.get("user","").lower()==user.lower():
      u["password"]=password; u["expires"]=expires; u["port"]=port; replaced=True; break
  if not replaced:
    users.append({"user":user,"password":password,"expires":expires,"port":port})
  save_users(users); sync_config_passwords()
  return build_view(msg="Saved & Synced")

@app.route("/delete", methods=["POST"])
def delete_user_html():
  if not require_login(): return redirect(url_for('login'))
  user = (request.form.get("user") or "").strip()
  if not user:
    return build_view(err="User လိုအပ်သည်")
  remain = [u for u in load_users() if (u.get("user","").lower() != user.lower())]
  save_users(remain)
  sync_config_passwords(mode="mirror")
  return build_view(msg=f"Deleted: {user}")

@app.route("/api/user.delete", methods=["POST"])
def delete_user_api():
  if not require_login():
    return make_response(jsonify({"ok": False, "err":"login required"}), 401)
  data = request.get_json(silent=True) or {}
  user = (data.get("user") or "").strip()
  if not user:
    return jsonify({"ok": False, "err": "user required"}), 400
  remain = [u for u in load_users() if (u.get("user","").lower() != user.lower())]
  save_users(remain)
  sync_config_passwords(mode="mirror")
  return jsonify({"ok": True})

@app.route("/api/users", methods=["GET","POST"])
def api_users():
  if not require_login():
    return make_response(jsonify({"ok": False, "err":"login required"}), 401)
  if request.method=="GET":
    users=load_users(); active=get_udp_listen_ports(); listen_port=get_listen_port_from_config()
    for u in users: u["status"]=status_for_user(u,active,listen_port)
    return jsonify(users)
  data=request.get_json(silent=True) or {}
  user=(data.get("user") or "").strip()
  password=(data.get("password") or "").strip()
  expires=(data.get("expires") or "").strip()
  port=str(data.get("port") or "").strip()
  if expires.isdigit():
    expires=(datetime.now()+timedelta(days=int(expires))).strftime("%Y-%m-%d")
  if not user or not password: return jsonify({"ok":False,"err":"user/password required"}),400
  if port and (not re.fullmatch(r"\d{2,5}",port) or not (6000<=int(port)<=19999)):
    return jsonify({"ok":False,"err":"invalid port"}),400
  if not port: port=pick_free_port()
  users=load_users(); replaced=False
  for u in users:
    if u.get("user","").lower()==user.lower():
      u["password"]=password; u["expires"]=expires; u["port"]=port; replaced=True; break
  if not replaced:
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
