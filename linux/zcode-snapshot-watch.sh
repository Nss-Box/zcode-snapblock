#!/usr/bin/env bash
# zcode-shield monitor: detect any local evidence of ZCode repo-snapshot activity.
# Alerts once per new finding (fingerprinted). Read-only wrt ~/.zcode.
set -u
ZCODE_HOME="${ZCODE_HOME:-$HOME/.zcode}"
SHIELD_DIR="${ZCODE_SHIELD_DIR:-$HOME/.zcode-shield}"
STATE_DIR="$SHIELD_DIR/watch-state"
ALERT_LOG="$SHIELD_DIR/alerts.log"
LOG_MAX_MB="${ZCODE_SHIELD_LOG_MAX_MB:-10}"
mkdir -p "$STATE_DIR"

rotate() {  # rotate <file> once it exceeds $LOG_MAX_MB (keeps one .1 generation)
  local f="$1"
  [ -f "$f" ] || return 0
  local size
  size="$(stat -c%s "$f" 2>/dev/null || echo 0)"
  if [ "$size" -gt $((LOG_MAX_MB * 1024 * 1024)) ]; then
    mv -f "$f" "$f.1" 2>/dev/null || true
  fi
}
rotate "$ALERT_LOG"
# blocked.log is rotated by mitm-addon.py itself (the writer); rotating it here
# as well races with the addon and can drop a line.

alert() {  # alert <severity> <fingerprint> <message>
  local sev="$1" fp="$2" msg="$3"
  local state="$STATE_DIR/$sev-$(printf '%s' "$fp" | sha256sum | cut -c1-16)"
  [ -e "$state" ] && return 0
  local stamp; stamp="$(date '+%F %T')"
  echo "[$stamp] [$sev] $msg" >> "$ALERT_LOG"
  logger -p user."$sev" -t zcode-shield "ALERT $msg" 2>/dev/null || true
  command -v notify-send >/dev/null 2>&1 && timeout 5 notify-send -u critical "ZCode 快照告警" "$msg" 2>/dev/null || true
  touch "$state"
}

# 1) snapshot artifact files anywhere under ~/.zcode
while IFS= read -r f; do
  [ -z "$f" ] && continue
  alert warning "artifact:$f" "检测到 ZCode 快照产物: $f (可能正在/已经打包上传, 检查 $ZCODE_HOME/v2/checkpoints/)"
done < <(find "$ZCODE_HOME" \( -name "*.tar.gz.enc" -o -name "*.envelope.json" \) -type f 2>/dev/null)

# 2) snapshot directories created
for d in "$ZCODE_HOME/v2/checkpoints" "$ZCODE_HOME/v2/repo-snapshots"; do
  [ -d "$d" ] && alert warning "dir:$d" "快照目录已出现: $d (说明服务端已对该账号开启 repo snapshot)"
done

# 3) today's log mentions upload-credential outside settings noise
LOG="$ZCODE_HOME/v2/logs/$(date '+%F').log"
if [ -f "$LOG" ] && grep -q "upload-credential" "$LOG" 2>/dev/null; then
  if ! grep -v "settingService" "$LOG" 2>/dev/null | grep -q "upload-credential"; then :; else
    alert warning "log:upload-credential" "日志出现 upload-credential 请求记录: $LOG"
  fi
fi

# 4) informational: shield blocked something (defense working, not a leak)
if [ -s "$SHIELD_DIR/blocked.log" ]; then
  alert info "blocked-evidence" "zcode-shield 已拦截过快照上传请求, 详见 $SHIELD_DIR/blocked.log (拦截=正常防御)"
fi
exit 0
