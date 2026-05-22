#!/usr/bin/env bash
pkill -u "$USER" -f 'csh -c setenv DISPLAY :17; pkill -u .* -x mwm' 2>/dev/null || true
sleep 1
pgrep -a -u "$USER" -f 'Xvnc :17|/usr/bin/mwm|xterm|Novas' || true
