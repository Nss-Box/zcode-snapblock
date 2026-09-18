#!/usr/bin/env bash
# Remove the zcode-shield proxy keys from ZCode's setting.json (restore direct
# connection). Usage: quit ZCode completely FIRST, then run this script.
set -euo pipefail

SETTING="${ZCODE_SETTING:-$HOME/.zcode/v2/setting.json}"

if ! command -v python3 >/dev/null 2>&1; then
  echo "[!] 需要 python3 (用于安全编辑 JSON)。安装后重试。" >&2
  exit 1
fi
if [ ! -f "$SETTING" ]; then
  echo "[!] 找不到 $SETTING" >&2
  exit 1
fi

python3 - "$SETTING" <<'PY'
import json, shutil, sys, os, time
p = sys.argv[1]
with open(p, encoding="utf-8") as f:
    d = json.load(f)
if "httpProxy" not in d and "httpProxyCaCertPath" not in d:
    print("未发现代理配置, 本来就是直连。")
    sys.exit(0)
bak = p + ".bak." + time.strftime("%Y%m%d%H%M%S")
shutil.copy2(p, bak)
d.pop("httpProxy", None)
d.pop("httpProxyCaCertPath", None)
tmp = p + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(d, f, ensure_ascii=False, indent=2)
os.replace(tmp, p)
print("已移除 httpProxy / httpProxyCaCertPath, 恢复直连。备份:", bak)
PY
echo "现在启动 ZCode 即恢复直连。"
