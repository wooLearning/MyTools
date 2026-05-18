#!/usr/bin/env bash
set -e

for i in 1 2 3 4 5; do
  pkill -9 -u "$USER" -f 'bash -lc cd ~/workspace; export DISPLAY=:17; export PATH=/tools/synopsys/verdi' 2>/dev/null || true
  sleep 1
done

export DISPLAY=:17
if command -v xterm >/dev/null 2>&1; then
  nohup xterm -geometry 120x35+60+60 -title 'Remote csh workspace' -e csh -c 'cd ~/workspace; echo "DISPLAY=$DISPLAY"; echo "csh/.cshrc environment ready"; exec csh' > "$HOME/.vnc/xterm-csh-display17.log" 2>&1 &
  echo "XTERM_CSH_PID=$!"
fi

if ! pgrep -u "$USER" -f '/tools/synopsys/verdi/W-2024.09-SP2/platform/LINUXAMD64/bin/Novas' >/dev/null 2>&1; then
  csh -c 'cd ~/workspace; setenv DISPLAY :17; /tools/synopsys/verdi/W-2024.09-SP2/bin/verdi >& ~/.vnc/verdi-display17-csh.log &' || true
  echo "VERDI_CSH_LAUNCH_REQUESTED"
else
  echo "VERDI_ALREADY_RUNNING"
fi

echo "--- status ---"
echo "broken_bash_count=$(pgrep -u "$USER" -f 'bash -lc cd ~/workspace; export DISPLAY=:17; export PATH=/tools/synopsys/verdi' | wc -l)"
pgrep -a -u "$USER" -f 'Xvnc :17|xterm|Novas|verdi' | head -30 || true
ss -ltn | grep 5917 || true
