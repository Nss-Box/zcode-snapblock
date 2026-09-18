#!/usr/bin/env bash
# zcode-shield Linux installer (systemd user units, no root needed).
# 1) resolves mitmdump + install dir on THIS machine
# 2) copies project files to the install dir
# 3) renders + enables the mitm service and the 30s monitor timer.
set -euo pipefail

SRC_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SHIELD_DIR="${ZCODE_SHIELD_DIR:-$HOME/.zcode-shield}"
PROXY_PORT="${ZCODE_SHIELD_PROXY_PORT:-18080}"
UNITS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

MITMDUMP="$(command -v mitmdump || true)"
if [ -z "$MITMDUMP" ]; then
  echo "[!] mitmdump not found. Install mitmproxy first (https://mitmproxy.org):"
  echo "      pipx install mitmproxy        # recommended"
  echo "      pip install --user mitmproxy  # or your distro's package manager"
  exit 1
fi

mkdir -p "$SHIELD_DIR" "$UNITS_DIR"
install -m 644 "$SRC_DIR/../mitm-addon.py" "$SHIELD_DIR/mitm-addon.py"
for f in zcode-snapshot-watch.sh enable-proxy.sh disable-proxy.sh; do
  install -m 755 "$SRC_DIR/$f" "$SHIELD_DIR/$f"
done

# Port config, consumed at render time below. First install writes it; to
# change the port later edit this file and re-run install.sh (units embed the
# port literally), then re-run enable-proxy.sh.
if [ ! -f "$SHIELD_DIR/proxy.env" ]; then
  printf 'PROXY_PORT=%s\n' "$PROXY_PORT" > "$SHIELD_DIR/proxy.env"
fi
PORT_NOW="$(sed -n 's/^PROXY_PORT=//p' "$SHIELD_DIR/proxy.env")"
if [ -z "$PORT_NOW" ]; then
  echo "[!] $SHIELD_DIR/proxy.env 存在但 PROXY_PORT 为空 — 请修正后重跑。" >&2
  exit 1
fi

# Render units: mitmdump path, install dir and port are resolved per machine
# here, so the repo itself contains no hardcoded absolute paths.
sed -e "s|__MITMDUMP__|$MITMDUMP|g" -e "s|__SHIELD_DIR__|$SHIELD_DIR|g" -e "s|__PORT__|$PORT_NOW|g" \
  "$SRC_DIR/systemd/zcode-shield-mitm.service.in" > "$UNITS_DIR/zcode-shield-mitm.service"
sed -e "s|__SHIELD_DIR__|$SHIELD_DIR|g" \
  "$SRC_DIR/systemd/zcode-snapshot-watch.service" > "$UNITS_DIR/zcode-snapshot-watch.service"
install -m 644 "$SRC_DIR/systemd/zcode-snapshot-watch.timer" "$UNITS_DIR/zcode-snapshot-watch.timer"

systemctl --user daemon-reload
systemctl --user enable --now zcode-shield-mitm.service
systemctl --user enable --now zcode-snapshot-watch.timer
systemctl --user restart zcode-shield-mitm.service

echo "[*] mitmdump: $MITMDUMP (127.0.0.1:$PORT_NOW)"
echo "[*] installed to: $SHIELD_DIR"
echo "[*] next: quit ZCode completely, then run:  $SHIELD_DIR/enable-proxy.sh"
echo "    verify: curl -x http://127.0.0.1:$PORT_NOW --cacert ~/.mitmproxy/mitmproxy-ca-cert.pem \\"
echo "              -o /dev/null -w '%{http_code}\\n' https://zcode.z.ai/api/v1/snapshot/upload-credential   # expect 403"
echo "    logs:   journalctl --user -u zcode-shield-mitm -f"
echo "    remove: $SRC_DIR/uninstall.sh"
