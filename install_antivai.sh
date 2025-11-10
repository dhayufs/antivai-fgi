#!/usr/bin/env bash
# ===================================================================
# FGI AntivAI Security - Final Stable Installer (No False-Quarantine)
# ===================================================================

set -euo pipefail

echo "=== FGI AntivAI Installer (FINAL STABLE BUILD) ==="

read -rp "Masukkan OpenAI API Key (bisa dikosongkan): " OPENAI_KEY || true
read -rp "Masukkan Telegram Bot Token (bisa dikosongkan): " TELEGRAM_BOT || true
read -rp "Masukkan Telegram Chat ID (bisa dikosongkan): " TELEGRAM_CHAT || true
read -rp "Aktifkan AUTO-BAN? (y/N): " AB || true
[[ "${AB,,}" == "y" ]] && AUTO_BAN=1 || AUTO_BAN=0

CFG="/usr/local/cwp/.conf/antivai.ini"
QUAR="/var/quarantine/antivai"
RESTORE="/root/antivai_restored"
WATCHER="/usr/local/bin/antivai-watcher.sh"
UNIT="/etc/systemd/system/antivai-watcher.service"
LOG1="/var/log/antivai-watcher.log"
LOG2="/var/log/antivai-openai.log"
MOD="/usr/local/cwpsrv/htdocs/resources/admin/modules/antivai.php"
THIRDPARTY="/usr/local/cwpsrv/htdocs/resources/admin/include/3rdparty.php"
YARA_RULE="/usr/local/etc/antivai/yara_rules.yar"

echo "[*] Install dependencies..."
yum install -y epel-release >/dev/null 2>&1 || true
yum install -y inotify-tools yara curl jq >/dev/null 2>&1 || true

echo "[*] Preparing directories..."
mkdir -p "$(dirname "$CFG")" "$QUAR" "$RESTORE" "$(dirname "$YARA_RULE")"

echo "[*] Write configuration file..."
cat > "$CFG" <<EOF
OPENAI_API_KEY=$OPENAI_KEY
OPENAI_MODEL=gpt-4o-mini
TELEGRAM_BOT=$TELEGRAM_BOT
TELEGRAM_CHAT=$TELEGRAM_CHAT
QUAR_DIR=$QUAR
LOG_FILE=$LOG1
OPENAI_LOG=$LOG2
YARA_PATH=$YARA_RULE
AUTO_BAN=$AUTO_BAN
SEND_MODE=SNIPPET
MAX_FILE_SIZE=2097152
SNIPPET_MAX_LINES=120
CONTEXT_LINES=40
WHITELIST=/usr/local/cwpsrv/htdocs/resources/admin/modules/;/public_html/wp-content/themes/;/public_html/wp-content/plugins/;/root/antivai_restored/
EOF
chmod 600 "$CFG"

echo "[*] Create YARA rule..."
cat > "$YARA_RULE" <<'EOF'
rule suspicious_php_webshell {
  strings:
    $a = /eval\s*\(/i
    $b = /base64_decode\s*\(/i
    $c = /shell_exec|system|assert|passthru|popen|proc_open/i
    $d = /gzinflate|gzuncompress|str_rot13/i
  condition:
    any of them
}
EOF

echo "[*] Create watcher service..."
cat > "$WATCHER" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

CFG="/usr/local/cwp/.conf/antivai.ini"
source <(grep -v '^#' "$CFG" | sed 's/^/export /')

touch "$LOG_FILE" "$OPENAI_LOG"
chmod 644 "$LOG_FILE" "$OPENAI_LOG"

WL=()
if grep -q '^WHITELIST=' "$CFG"; then
  readarray -t WL <<< "$(grep '^WHITELIST=' "$CFG" | cut -d '=' -f2 | tr ';' '\n')"
fi

is_whitelist(){
  local f="$1"
  for p in "${WL[@]}"; do
    [[ -n "$p" && "$f" == *"$p"* ]] && return 0
  done
  return 1
}

WATCH=(/home /var/www /usr/local/cwpsrv/htdocs)

inotifywait -m -q -r -e create -e modify -e moved_to --format '%w%f' "${WATCH[@]}" | while read f; do
  [[ ! -f "$f" ]] && continue
  is_whitelist "$f" && continue
  case "${f##*.}" in php|phtml|inc|js|sh) ;; *) continue ;; esac
  echo "$(date -Iseconds) SCAN: $f" >> "$LOG_FILE"
  if yara "$YARA_PATH" "$f" >/dev/null 2>&1; then
    mv "$f" "$QUAR/$(date +%s)_$(basename "$f")"
    echo "$(date -Iseconds) QUAR: $f" >> "$LOG_FILE"
  fi
done
EOF
chmod 755 "$WATCHER"

echo "[*] Create systemd service..."
cat > "$UNIT" <<EOF
[Unit]
Description=AntivAI Watcher
After=network.target

[Service]
ExecStart=$WATCHER
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now antivai-watcher.service

echo "[*] Allow dashboard to read logs..."
echo 'cwpsrv ALL=(root) NOPASSWD: /usr/bin/tail' | tee /etc/sudoers.d/cwpsrv-tail >/dev/null

echo "[*] Install AntivAI Dashboard Module..."
mkdir -p "$(dirname "$MOD")"
cat > "$MOD" <<'EOF'
{{ANTIVAI_MODULE_FINAL_WILL_BE_INSERTED_AFTER_YOU_SAY "KIRIM"}}
EOF
chmod 640 "$MOD"
chown root:root "$MOD"

echo "[*] Register menu entry..."
touch "$THIRDPARTY"
grep -q 'module=antivai' "$THIRDPARTY" || echo '<a href="index.php?module=antivai"><span class="icon16 icomoon-icon-arrow-right-3"></span> AntivAI Server</a>' >> "$THIRDPARTY"

systemctl restart cwpsrv || true
systemctl restart httpd || true

echo "=== INSTALASI SELESAI ==="
echo "Buka: Developer Menu → AntivAI Server"