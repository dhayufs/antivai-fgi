#!/usr/bin/env bash
# Safe Uninstall for FGI AntivAI Security
# - stops service, disables systemd, moves files to backup folder
# - removes menu entry from 3rdparty.php
# - removes sudoers entry created for tail
# - does NOT delete quarantine files (left as evidence)
# - example tested commands for CentOS/Alma/Rocky
set -euo pipefail

TS=$(date +%Y%m%d_%H%M%S)
BACKUP="/root/antivai-uninstall-${TS}"
mkdir -p "$BACKUP"

echo "== FGI AntivAI Uninstall (safe) =="
echo "Backing up important files to: $BACKUP"
sleep 1

# 1) Stop & disable service
if systemctl list-units --full -all | grep -q "antivai-watcher"; then
  echo "[*] Stopping & disabling antivai-watcher.service"
  systemctl stop antivai-watcher.service 2>/dev/null || true
  systemctl disable antivai-watcher.service 2>/dev/null || true
  systemctl daemon-reload
fi

# 2) Move scripts, unit, helper, logs, config to backup
FILES=(
  "/usr/local/bin/antivai-watcher.sh"
  "/usr/local/bin/antivai-ban.sh"
  "/etc/systemd/system/antivai-watcher.service"
  "/usr/local/cwp/.conf/antivai.ini"
  "/usr/local/etc/antivai/yara_rules.yar"
  "/var/log/antivai-watcher.log"
  "/var/log/antivai-openai.log"
  "/usr/local/cwpsrv/htdocs/resources/admin/modules/antivai.php"
)

for f in "${FILES[@]}"; do
  if [ -e "$f" ]; then
    echo "[*] Moving $f -> $BACKUP/"
    mv -f "$f" "$BACKUP/" || echo "WARN: cannot move $f (permission?)"
  fi
done

# 3) Backup and preserve quarantine (do not delete)
if [ -d "/var/quarantine/antivai" ]; then
  echo "[*] Quarantine folder left in place: /var/quarantine/antivai"
  echo "    (If you want to backup, it's located at: $BACKUP/quarantine)"
  mkdir -p "$BACKUP/quarantine"
  cp -a /var/quarantine/antivai "$BACKUP/quarantine/" 2>/dev/null || true
fi

# 4) Remove menu entry from 3rdparty.php (Developer Menu)
THIRDPARTY="/usr/local/cwpsrv/htdocs/resources/admin/include/3rdparty.php"
if [ -f "$THIRDPARTY" ]; then
  echo "[*] Removing AntivAI menu entry from $THIRDPARTY (backup first)"
  cp -a "$THIRDPARTY" "$BACKUP/3rdparty.php.bak"
  # remove lines matching module=antivai block (simple and safe)
  sed -i.bak '/module=antivai/d' "$THIRDPARTY" || true
  # if file left empty, restore original backup
  if [ ! -s "$THIRDPARTY" ]; then
    mv -f "$BACKUP/3rdparty.php.bak" "$THIRDPARTY"
    echo "Note: 3rdparty.php would have been empty so original restored."
  fi
fi

# 5) Remove cwpsrv-tail sudoers entry if it matches exactly our line
SUDOFILE="/etc/sudoers.d/cwpsrv-tail"
if [ -f "$SUDOFILE" ]; then
  echo "[*] Removing sudoers file $SUDOFILE"
  # only remove if it contains our expected line
  if grep -q "cwpsrv ALL=(root) NOPASSWD: /usr/bin/tail" "$SUDOFILE" 2>/dev/null; then
    rm -f "$SUDOFILE"
  else
    echo "  Note: $SUDOFILE exists but doesn't match expected content; preserved as backup."
    mv -f "$SUDOFILE" "$BACKUP/" || true
  fi
fi

# 6) Remove /etc/sudoers.d entries that may include our tail rule in other files (try safe cleanup)
if grep -Rqs "cwpsrv ALL=(root) NOPASSWD: /usr/bin/tail" /etc/sudoers.d 2>/dev/null; then
  echo "[*] Found sudoers entries referencing tail; leaving them for manual review but backing up all sudoers.d to uninstall backup"
  tar -czf "$BACKUP/sudoers.d-backup.tar.gz" -C /etc sudoers.d 2>/dev/null || true
fi

# 7) Remove systemd unit file if any left
if [ -f "/etc/systemd/system/antivai-watcher.service" ]; then
  rm -f /etc/systemd/system/antivai-watcher.service
  systemctl daemon-reload || true
fi

# 8) Remove menu JS injection (if used)
CFG_JS="/usr/local/cwpsrv/htdocs/resources/admin/include/configserver.php"
if [ -f "$CFG_JS" ]; then
  cp -a "$CFG_JS" "$BACKUP/configserver.php.bak"
  # remove lines that reference antivai menu via JS append (best-effort)
  sed -i.bak '/antivai/d' "$CFG_JS" || true
fi

# 9) Remove web module include if it exists anywhere else
find /usr/local/cwpsrv/htdocs -type f -name "*antivai*.php" -not -path "$BACKUP/*" -print0 | while read -r -d '' file; do
  echo "[*] Moving $file to backup"
  mv -f "$file" "$BACKUP/" || true
done

echo
echo "== DONE =="
echo "Backup of removed/modified files is at: $BACKUP"
echo "Quarantine folder kept at /var/quarantine/antivai (copied to backup/quarantine)."
echo
echo "Manual checks recommended:"
echo " - Verify no other cron/jobs reference antivai scripts."
echo " - If you want to remove quarantine folder, do it manually after review."
echo
