@echo off
rem ============================================================
rem  Avvia_hub.bat - avvia l'hub Django sul tuo PC e apre il browser
rem  Doppio clic per avviare. Per fermare: chiudi la finestra "Hub".
rem  PostgreSQL non va avviato: e' un servizio di Windows, parte da solo.
rem ============================================================

rem vai nella cartella di questo file (C:\Users\adeim\projects\hub)
cd /d "%~dp0"

rem avvia il server Django in una finestra separata chiamata "Hub"
start "Hub" cmd /k "uv run manage.py runserver"

rem aspetta qualche secondo che il server sia pronto, poi apre il browser
timeout /t 4 /nobreak >nul
start "" http://127.0.0.1:8000/confronto/
