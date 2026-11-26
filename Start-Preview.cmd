@echo off
setlocal
set "HKRR_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "HKRR_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%HKRR_PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Run-HKRR.ps1"
pause
