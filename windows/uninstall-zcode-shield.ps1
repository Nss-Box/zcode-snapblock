# Remove zcode-shield from Windows: unregister both scheduled tasks and
# (optionally) delete the install dir. Does NOT uninstall mitmproxy itself.
# Usage: run disable-proxy.ps1 (with ZCode quit) BEFORE this script.
param(
  [string]$InstallDir = "$env:USERPROFILE\.zcode-shield",
  [switch]$RemoveFiles
)
$ErrorActionPreference = 'Stop'

$setting = "$env:USERPROFILE\.zcode\v2\setting.json"
if (Test-Path $setting) {
  try {
    $cfg = Get-Content $setting -Raw -Encoding UTF8 | ConvertFrom-Json
  } catch {
    Write-Warning "could not parse $setting - make sure httpProxy is removed manually"
    $cfg = $null
  }
  if ($cfg -and $cfg.PSObject.Properties['httpProxy']) {
    throw "setting.json still contains httpProxy. Quit ZCode, run disable-proxy.ps1 first, then re-run uninstall."
  }
}

foreach ($task in 'zcode-shield-mitm', 'zcode-snapshot-watch') {
  $existed = [bool](Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue)
  Stop-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
  Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction SilentlyContinue
  if ($existed) { Write-Host "[*] removed task: $task" } else { Write-Host "[*] task not present: $task" }
}
# Belt and braces: kill OUR mitmdump and its run-mitm.ps1 powershell wrapper
# (the wrapper holds the mitmdump.log handle open). Filtered by command line
# so unrelated user-owned mitmproxy sessions are never touched.
Get-CimInstance Win32_Process -Filter "Name='mitmdump.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -like '*zcode-shield*' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -like '*run-mitm.ps1*' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

if ($RemoveFiles) {
  if (Test-Path $InstallDir) {
    # Stop-ScheduledTask kills the process tree asynchronously; a handle on
    # mitmdump.log can outlive it briefly. Retry so we never leave the dir
    # half-deleted (Remove-Item stops at the first locked file).
    $removed = $false
    foreach ($attempt in 1..10) {
      try { Remove-Item -Recurse -Force $InstallDir -ErrorAction Stop; $removed = $true; break }
      catch { Start-Sleep -Milliseconds 500 }
    }
    if ($removed) {
      Write-Host "[*] removed dir: $InstallDir"
    } else {
      Write-Warning "could not fully delete $InstallDir (a file is still locked). Remaining files:"
      Get-ChildItem -Recurse $InstallDir -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "    $($_.FullName)" }
      Write-Warning "close the locking process and delete the directory manually (safe to do after a reboot)."
    }
  } else {
    Write-Host "[*] install dir not present: $InstallDir"
  }
} else {
  Write-Host "[*] kept install dir: $InstallDir (re-run with -RemoveFiles to delete it)"
}
Write-Host "[*] mitmproxy itself was left installed (winget uninstall mitmproxy.mitmproxy if you don't need it)"
