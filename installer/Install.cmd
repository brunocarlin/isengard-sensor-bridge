@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-CpuTempStandaloneFix.ps1" %*
pause
