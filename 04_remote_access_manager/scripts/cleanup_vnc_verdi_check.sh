#!/usr/bin/env bash
set -e
echo "--- before broken launcher count ---"
pgrep -u "$USER" -f 'bash -lc cd ~/workspace; export DISPLAY=:17; export PATH=/tools/synopsys/verdi' | wc -l
pkill -u "$USER" -f 'bash -lc cd ~/workspace; export DISPLAY=:17; export PATH=/tools/synopsys/verdi' 2>/dev/null || true
sleep 2
echo "--- Xvnc ---"
pgrep -a -u "$USER" -f 'Xvnc :17' || true
echo "--- Verdi/Novas ---"
pgrep -a -u "$USER" -f '/tools/synopsys/verdi/W-2024.09-SP2|Novas|verdi' | head -20 || true
echo "--- VNC listen ---"
ss -ltn | grep 5917 || true
echo "--- broken launcher count after ---"
pgrep -u "$USER" -f 'bash -lc cd ~/workspace; export DISPLAY=:17; export PATH=/tools/synopsys/verdi' | wc -l
echo "--- Verdi log tail ---"
tail -30 "$HOME/.vnc/verdi-display17.log" 2>/dev/null || true
