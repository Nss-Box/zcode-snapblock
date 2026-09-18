# zcode-shield monitor for Windows - detect ZCode repo-snapshot artifacts.
# Schedule with Task Scheduler (see setup-zcode-shield.ps1) every 30s.
# Read-only with respect to ~/.zcode; alerts once per finding (fingerprinted).
param(
  [string]$ZcodeHome = "$env:USERPROFILE\.zcode",
  [string]$ShieldDir = "$env:USERPROFILE\.zcode-shield",
  [int]$LogMaxMB = 10
)
$ErrorActionPreference = 'SilentlyContinue'
$StateDir = Join-Path $ShieldDir 'watch-state'
$AlertLog = Join-Path $ShieldDir 'alerts.log'
New-Item -ItemType Directory -Force -Path $StateDir | Out-Null

# Keep logs bounded: rotate to *.log.1 past $LogMaxMB. Best effort - files held
# open by a running process (mitmdump.log) simply retry on a later tick.
# blocked.log is NOT listed: mitm-addon.py rotates its own log (the writer);
# rotating it here too would race with the addon and can drop a line.
foreach ($log in @((Join-Path $ShieldDir 'mitmdump.log'), $AlertLog)) {
  if ((Test-Path $log) -and ((Get-Item $log).Length -gt ($LogMaxMB * 1MB))) {
    Remove-Item "$log.1" -ErrorAction SilentlyContinue
    Move-Item $log "$log.1" -ErrorAction SilentlyContinue
  }
}

function Show-Toast([string]$Title, [string]$Message) {
  # Win10/11 built-in toast, no third-party modules.
  try {
    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
    [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom, ContentType = WindowsRuntime] | Out-Null
    $safeTitle = [System.Security.SecurityElement]::Escape($Title)
    $safeMsg = [System.Security.SecurityElement]::Escape($Message)
    $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
    $xml.LoadXml("<toast><visual><binding template=`"ToastGeneric`"><text>$safeTitle</text><text>$safeMsg</text></binding></visual></toast>")
    $toast = New-Object Windows.UI.Notifications.ToastNotification $xml
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('zcode-shield').Show($toast)
  } catch { }
}

function Alert([string]$Sev, [string]$Fp, [string]$Message) {
  $tag = -join ([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($Fp))[0..7] | ForEach-Object { $_.ToString('x2') })
  $state = Join-Path $StateDir "$Sev-$tag"
  if (Test-Path $state) { return }
  $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  Add-Content -Path $AlertLog -Value "[$stamp] [$Sev] $Message" -Encoding UTF8
  Show-Toast 'ZCode 快照告警' $Message
  # Windows Event Log channel: only works if an admin pre-registered the
  # 'zcode-shield' source; SourceExists throws for non-admin users, which the
  # catch swallows. Toast + alerts.log are the always-working channels.
  try {
    if (-not [System.Diagnostics.EventLog]::SourceExists('zcode-shield')) {
      [System.Diagnostics.EventLog]::CreateEventSource('zcode-shield', 'Application')
    }
    [System.Diagnostics.EventLog]::WriteEntry('zcode-shield', "ALERT $Message", 'Warning', 1)
  } catch { }
  New-Item -ItemType File -Path $state | Out-Null
}

# 0) watchdog: keep the mitmdump task alive (self-heal within one 30s tick,
#    independent of Task Scheduler's restart-on-failure policy). The process
#    check matches only OUR instance (command line contains 'zcode-shield') so
#    a user-run mitmproxy never masks a dead shield.
$mitmTask = Get-ScheduledTask -TaskName 'zcode-shield-mitm' -ErrorAction SilentlyContinue
$shieldMitm = Get-CimInstance Win32_Process -Filter "Name='mitmdump.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -like '*zcode-shield*' }
if ($mitmTask -and $mitmTask.State -ne 'Running' -and -not $shieldMitm) {
  Start-ScheduledTask -TaskName 'zcode-shield-mitm' -ErrorAction SilentlyContinue
}

# 1) artifact files
Get-ChildItem -Path $ZcodeHome -Recurse -File -Include *.tar.gz.enc, *.envelope.json |
  ForEach-Object { Alert 'warning' "artifact:$($_.FullName)" "检测到 ZCode 快照产物: $($_.FullName) (检查 $ZcodeHome\v2\checkpoints\)" }

# 2) snapshot directories
@('v2\checkpoints', 'v2\repo-snapshots') | ForEach-Object {
  $d = Join-Path $ZcodeHome $_
  if (Test-Path $d) { Alert 'warning' "dir:$d" "快照目录已出现: $d (服务端已对该账号开启 repo snapshot)" }
}

# 3) today's log mentions upload-credential (excluding settings-write noise)
$log = Join-Path $ZcodeHome ("v2\logs\{0}.log" -f (Get-Date -Format 'yyyy-MM-dd'))
if (Test-Path $log) {
  $hit = Select-String -Path $log -Pattern 'upload-credential' | Where-Object { $_.Line -notmatch 'settingService' }
  if ($hit) { Alert 'warning' 'log:upload-credential' "日志出现 upload-credential 请求记录: $log" }
}

# 4) informational: shield blocked something
$blocked = Join-Path $ShieldDir 'blocked.log'
if ((Test-Path $blocked) -and (Get-Item $blocked).Length -gt 0) {
  Alert 'info' 'blocked-evidence' "zcode-shield 已拦截过快照上传请求, 详见 $blocked (拦截=正常防御)"
}
