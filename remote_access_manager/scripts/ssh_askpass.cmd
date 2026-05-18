@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0ssh_askpass.ps1" %*
