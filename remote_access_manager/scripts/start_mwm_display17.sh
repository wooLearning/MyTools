#!/usr/bin/env bash
set -e
export DISPLAY=:17
pkill -u "$USER" -x mwm 2>/dev/null || true
sleep 1
nohup /usr/bin/mwm > "$HOME/.vnc/mwm-display17.log" 2>&1 &
echo "MWM_PID=$!"
sleep 2
echo "--- status ---"
pgrep -a -u "$USER" -f 'Xvnc :17|mwm|xterm|Novas' || true
echo "--- mwm log ---"
tail -30 "$HOME/.vnc/mwm-display17.log" 2>/dev/null || true
