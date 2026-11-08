@echo off
rem Trascina il file yomitan-dictionaries-....json sopra questo file.
chcp 65001 >nul
set PYTHONIOENCODING=utf-8
where py >nul 2>nul && (py "%~dp0converti_export_yomitan.py" "%~1") || (python "%~dp0converti_export_yomitan.py" "%~1")
pause
