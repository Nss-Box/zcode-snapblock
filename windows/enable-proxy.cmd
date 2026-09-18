@echo off
rem zcode-shield: enable interception proxy (wrapper - runs from cmd, PowerShell, or double-click).
rem %~dp0 = this script's directory, so no hardcoded user paths. Args pass through.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0enable-proxy.ps1" %*
