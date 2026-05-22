@echo off
setlocal
cd /d "%~dp0\.."

py -3 -m PyInstaller ^
  --noconfirm ^
  --clean ^
  --onefile ^
  --windowed ^
  --distpath . ^
  --name CodexRemoteControl ^
  launcher.py

if errorlevel 1 (
  echo.
  echo Packaging failed.
  exit /b 1
)

echo.
echo Built: CodexRemoteControl.exe
