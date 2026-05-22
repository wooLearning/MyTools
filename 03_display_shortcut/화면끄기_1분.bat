@echo off
powercfg /change monitor-timeout-ac 1
echo Screen timeout set to 1 minute for AC.
timeout /t 2 >nul