@echo off
powercfg /change monitor-timeout-ac 60
echo Screen timeout set to 60 minute for AC.
timeout /t 2 >nul