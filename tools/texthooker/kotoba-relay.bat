@echo off
rem Avvia kotoba-relay.ps1 (doppio clic). Puoi anche scrivere: kotoba-relay.bat 192.168.1.34
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0kotoba-relay.ps1" %*
pause
