#!/usr/bin/env bash
set -e
pkill -u "$USER" -f 'xterm .*csh workspace' 2>/dev/null || true
sleep 1
export DISPLAY=:17
nohup xterm \
  -fa Monospace \
  -fs 10 \
  -geometry 100x16+20+720 \
  -bg black \
  -fg white \
  -title 'Remote csh workspace' \
  -e csh -c 'cd ~/workspace; echo "DISPLAY=$DISPLAY"; echo "csh/.cshrc environment ready"; exec csh' \
  > "$HOME/.vnc/xterm-csh-display17.log" 2>&1 &
echo "XTERM_RELAUNCHED=$!"
sleep 1
echo "--- status ---"
pgrep -a -u "$USER" -f 'Xvnc :17|xterm|Novas' | head -20 || true
