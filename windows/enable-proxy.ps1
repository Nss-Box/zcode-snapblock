# Point ZCode at the zcode-shield proxy by adding httpProxy keys to setting.json.
# Usage: quit ZCode completely FIRST, then run this script, then start ZCode.
# Idempotent: safe to run repeatedly. Validates JSON before writing; always backs up.
param(
  [int]$ProxyPort = 18080,
  [string]$SettingPath = "$env:USERPROFILE\.zcode\v2\setting.json"
)
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $SettingPath)) {
  throw "setting.json not found: $SettingPath (start ZCode once so it creates the file, then re-run)"
}
$ca = Join-Path $env:USERPROFILE '.mitmproxy\mitmproxy-ca-cert.pem'
if (-not (Test-Path $ca)) {
  throw "mitmproxy CA cert not found: $ca (run setup-zcode-shield.ps1 first, or run mitmdump once manually)"
}

# The CA file survives uninstall, so its presence proves nothing - the proxy
# itself must be listening, or ZCode would point at a dead port and every
# login/chat request would fail with no obvious cause.
function Test-LocalPort([int]$Port) {
  $client = New-Object Net.Sockets.TcpClient
  try {
    $async = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
    if ($async.AsyncWaitHandle.WaitOne(500)) { $client.EndConnect($async); return $true }
    return $false
  } catch { return $false } finally { $client.Close() }
}
if (-not (Test-LocalPort $ProxyPort)) {
  throw "no proxy listening on 127.0.0.1:$ProxyPort - run setup-zcode-shield.ps1 first (or check: Get-ScheduledTask zcode-shield-mitm)"
}

if (Get-Process -Name ZCode -ErrorAction SilentlyContinue) {
  Write-Warning "ZCode is currently running: proxy settings are read at startup and may be overwritten when it exits. Quit ZCode, re-run this script, then start ZCode."
}

try {
  $cfg = Get-Content $SettingPath -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
  throw "setting.json is not valid JSON, aborting: $_"
}

$bak = "{0}.bak-{1:yyyyMMddHHmmss}" -f $SettingPath, (Get-Date)
Copy-Item $SettingPath $bak

if (-not ($cfg.PSObject.Properties['httpProxy'])) { $cfg | Add-Member NoteProperty httpProxy $null }
$cfg.httpProxy = "http://127.0.0.1:$ProxyPort"
if (-not ($cfg.PSObject.Properties['httpProxyCaCertPath'])) { $cfg | Add-Member NoteProperty httpProxyCaCertPath $null }
$cfg.httpProxyCaCertPath = $ca

# UTF8Encoding($false): UTF-8 without BOM, which JSON parsers prefer.
[System.IO.File]::WriteAllText($SettingPath, ($cfg | ConvertTo-Json -Depth 100), (New-Object System.Text.UTF8Encoding $false))

Write-Host "[*] enabled: httpProxy=http://127.0.0.1:$ProxyPort  httpProxyCaCertPath=$ca"
Write-Host "[*] backup : $bak"
Write-Host "[*] start ZCode now. Verify with:"
Write-Host "    curl.exe --ssl-no-revoke -x http://127.0.0.1:$ProxyPort --cacert `"$ca`" -o NUL -w `"%{http_code}`" https://zcode.z.ai/api/v1/snapshot/upload-credential  (expect 403)"
Write-Host "[*] to revert: run disable-proxy.ps1 (quit ZCode first)"
