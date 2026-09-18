# Remove the zcode-shield proxy keys from ZCode's setting.json (restore direct connection).
# Usage: quit ZCode completely FIRST, then run this script, then start ZCode.
param(
  [string]$SettingPath = "$env:USERPROFILE\.zcode\v2\setting.json"
)
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $SettingPath)) {
  throw "setting.json not found: $SettingPath (nothing to do)"
}

# Record intent BEFORE touching the file: running disable at all means "stay
# direct", so the monitor's auto-repair must stop re-adding the keys on its
# next 30s tick (ZcodeSnapshotWatch.ps1 section 5 checks this flag).
# $PSScriptRoot = the install dir.
New-Item -ItemType File -Path (Join-Path $PSScriptRoot 'proxy-disabled.flag') -Force | Out-Null

try {
  $cfg = Get-Content $SettingPath -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
  throw "setting.json is not valid JSON, aborting: $_"
}

$hasProxy = $cfg.PSObject.Properties['httpProxy'] -or $cfg.PSObject.Properties['httpProxyCaCertPath']
if (-not $hasProxy) {
  Write-Host "[*] proxy keys not present - nothing to remove (already direct connection)"
  return
}

$bak = "{0}.bak-{1:yyyyMMddHHmmss}" -f $SettingPath, (Get-Date)
Copy-Item $SettingPath $bak

foreach ($key in 'httpProxy', 'httpProxyCaCertPath') {
  if ($cfg.PSObject.Properties[$key]) { $cfg.PSObject.Properties.Remove($key) }
}
[System.IO.File]::WriteAllText($SettingPath, ($cfg | ConvertTo-Json -Depth 100), (New-Object System.Text.UTF8Encoding $false))

Write-Host "[*] removed httpProxy / httpProxyCaCertPath - direct connection restored"
Write-Host "[*] backup : $bak"
Write-Host "[*] start ZCode now."
