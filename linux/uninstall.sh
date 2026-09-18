#!/usr/bin/env bash
# Remove zcode-shield from Linux: stop + disable the user units, delete unit
# files, optionally remove the install dir. Does NOT uninstall mitmproxy.
# Usage: run disable-proxy.sh (with ZCode quit) BEFORE this script.
# Pass --remove-files to also delete the install dir.
set -euo pipefail

SHIELD_DIR="${ZCODE_SHIELD_DIR:-$HOME/.zcode-shield}"
UNITS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
SETTING="${ZCODE_SETTING:-$HOME/.zcode/v2/setting.json}"

if [ -f "$SETTING" ] && grep -q '"httpProxy"' "$SETTING" 2>/dev/null; then
  echo "[!] $SETTING still contains httpProxy."
  echo "    Quit ZCode, run $SHIELD_DIR/disable-proxy.sh first, then re-run uninstall."
  exit 1
fi

systemctl --user disable --now zcode-shield-mitm.service zcode-snapshot-watch.timer 2>/dev/null || true
rm -f "$UNITS_DIR/zcode-shield-mitm.service" \
      "$UNITS_DIR/zcode-snapshot-watch.service" \
      "$UNITS_DIR/zcode-snapshot-watch.timer"
systemctl --user daemon-reload
echo "[*] user units removed"

if [ "${1:-}" = "--remove-files" ]; then
  rm -rf "$SHIELD_DIR"
  echo "[*] removed dir: $SHIELD_DIR"
else
  echo "[*] kept install dir: $SHIELD_DIR (re-run with --remove-files to delete it)"
fi
echo "[*] mitmproxy itself was left installed (pipx uninstall mitmproxy / package manager if you don't need it)"
