"""
zcode-shield — mitmproxy addon
Path-level blocking of ZCode workspace snapshot upload (repo snapshot).

Rules:
  1. Any host, path starts with /api/v1/snapshot/  -> 403
     (covers https://zcode.z.ai and fallback https://zcode.chatglm.site;
      the only snapshot endpoint in app.asar 3.12.3 is /api/v1/snapshot/upload-credential)
  2. PUT whose path contains "repo_snapshot_"     -> 403
     (belt & suspenders: OSS direct-upload object keys are built from
      repo_snapshot_encrypted_artifact/v2, repo_snapshot_delta/v2, ...)
  3. Everything else passes through untouched.

Blocked requests are appended to <SHIELD_DIR>/blocked.log and logged loudly.
Works on Linux and Windows (mitmproxy runs on both; paths via os.path.expanduser).
"""
import os
from datetime import datetime

from mitmproxy import ctx, http

SHIELD_DIR = os.environ.get("ZCODE_SHIELD_DIR") or os.path.join(
    os.path.expanduser("~"), ".zcode-shield"
)
BLOCK_LOG = os.path.join(SHIELD_DIR, "blocked.log")
BLOCK_LOG_MAX_BYTES = 10 * 1024 * 1024

SNAPSHOT_PATH_PREFIXES = ("/api/v1/snapshot/",)
OSS_KEY_MARKER = "repo_snapshot_"


def _append_block(line: str) -> None:
    try:
        os.makedirs(SHIELD_DIR, exist_ok=True)
        try:
            if os.path.getsize(BLOCK_LOG) > BLOCK_LOG_MAX_BYTES:
                os.replace(BLOCK_LOG, BLOCK_LOG + ".1")
        except OSError:
            pass
        with open(BLOCK_LOG, "a", encoding="utf-8") as f:
            f.write(line)
    except OSError:
        pass


def _log_block(flow: http.HTTPFlow, rule: str) -> None:
    line = (
        f"{datetime.now().isoformat(timespec='seconds')} BLOCKED rule={rule} "
        f"{flow.request.method} {flow.request.host}{flow.request.path}\n"
    )
    _append_block(line)
    ctx.log.warn(
        "zcode-shield BLOCKED %s %s%s (rule=%s)"
        % (flow.request.method, flow.request.host, flow.request.path, rule)
    )


def request(flow: http.HTTPFlow) -> None:
    path = (flow.request.path or "/").split("?", 1)[0]

    if any(path.startswith(p) for p in SNAPSHOT_PATH_PREFIXES):
        _log_block(flow, "snapshot-api")
        flow.response = http.Response.make(
            403,
            b'{"code":403,"msg":"blocked by zcode-shield"}',
            {"Content-Type": "application/json"},
        )
        return

    if flow.request.method == "PUT" and OSS_KEY_MARKER in path:
        _log_block(flow, "oss-artifact")
        flow.response = http.Response.make(
            403, b"blocked by zcode-shield", {"Content-Type": "text/plain"}
        )
