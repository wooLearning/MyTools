@echo off
setlocal
cd /d "%~dp0\.."
python -m codex_remote_gui.app
if errorlevel 1 (
  echo.
  echo Failed to start with python. Trying py -3...
  py -3 -m codex_remote_gui.app
)
