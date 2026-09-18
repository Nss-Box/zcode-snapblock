#!/usr/bin/env bash
# Point ZCode at the zcode-shield proxy by adding httpProxy keys to setting.json.
# Usage: quit ZCode completely FIRST, then run this script, then start ZCode.
# Idempotent: safe to run repeatedly. Validates JSON before writing; always backs up.
set -euo pipefail

SHIELD_DIR="${ZCODE_SHIELD_DIR:-$HOME/.zcode-shield}"
SETTING="${ZCODE_SETTING:-$HOME/.zcode/v2/setting.json}"
PORT="$(sed -n 's/^PROXY_PORT=//p' "$SHIELD_DIR/proxy.env" 2>/dev/null || true)"
PORT="${PORT:-18080}"

if ! command -v python3 >/dev/null 2>&1; then
  echo "[!] 需要 python3 (用于安全编辑 JSON)。安装后重试。" >&2
  exit 1
fi
if [ ! -f "$SETTING" ]; then
  echo "[!] 找不到 $SETTING — 先启动一次 ZCode 让它生成配置文件。" >&2
  exit 1
fi
CA="$HOME/.mitmproxy/mitmproxy-ca-cert.pem"
if [ ! -f "$CA" ]; then
  echo "[!] mitmproxy CA 不存在: $CA — 先运行 install.sh (或手动运行一次 mitmdump)。" >&2
  exit 1
fi
# CA 文件在卸载后仍保留, 它存在不等于代理活着 — 端口必须真的在监听,
# 否则 ZCode 会指向死端口, 登录/对话全部失败且难以定位。
if ! timeout 1 bash -c "</dev/tcp/127.0.0.1/$PORT" 2>/dev/null; then
  echo "[!] 127.0.0.1:$PORT 没有代理在监听 — 先运行 install.sh (或检查: systemctl --user status zcode-shield-mitm)。" >&2
  exit 1
fi
if pgrep -if zcode >/dev/null 2>&1; then
  echo "[!] ZCode 正在运行: 代理设置仅在启动时读取, 退出时还可能覆盖写回。建议完全退出 ZCode 后重跑本脚本。" >&2
fi

python3 - "$SETTING" "$PORT" "$CA" <<'PY'
import json, shutil, sys, os, time
p, port, ca = sys.argv[1], sys.argv[2], sys.argv[3]
with open(p, encoding="utf-8") as f:
    d = json.load(f)  # invalid JSON aborts here, file untouched
bak = p + ".bak." + time.strftime("%Y%m%d%H%M%S")
shutil.copy2(p, bak)
d["httpProxy"] = "http://127.0.0.1:%s" % port
d["httpProxyCaCertPath"] = ca
tmp = p + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(d, f, ensure_ascii=False, indent=2)
os.replace(tmp, p)
print("已启用: httpProxy=http://127.0.0.1:%s  httpProxyCaCertPath=%s" % (port, ca))
print("备份:", bak)
PY

echo "现在启动 ZCode 即生效。验证:"
echo "  curl -x http://127.0.0.1:$PORT --cacert ~/.mitmproxy/mitmproxy-ca-cert.pem -o /dev/null -w '%{http_code}\n' https://zcode.z.ai/api/v1/snapshot/upload-credential   # 期望 403"
echo "恢复直连: 完全退出 ZCode 后运行 disable-proxy.sh"
