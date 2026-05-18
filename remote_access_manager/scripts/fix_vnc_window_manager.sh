#!/usr/bin/env bash
set -e

export DISPLAY=:17

echo "--- available window managers ---"
for c in openbox metacity xfwm4 twm fluxbox icewm mwm; do
  printf "%s=" "$c"
  command -v "$c" || true
done

echo "--- remove xterm ---"
pkill -u "$USER" -f 'xterm .*csh workspace' 2>/dev/null || true
pkill -u "$USER" -x xterm 2>/dev/null || true

echo "--- start window manager if missing ---"
if pgrep -u "$USER" -f 'openbox|metacity|xfwm4|twm|fluxbox|icewm|mwm' >/dev/null 2>&1; then
  echo "WINDOW_MANAGER_ALREADY_RUNNING"
else
  if command -v openbox >/dev/null 2>&1; then
    nohup openbox > "$HOME/.vnc/window-manager-display17.log" 2>&1 &
    echo "STARTED=openbox PID=$!"
  elif command -v metacity >/dev/null 2>&1; then
    nohup metacity --replace > "$HOME/.vnc/window-manager-display17.log" 2>&1 &
    echo "STARTED=metacity PID=$!"
  elif command -v xfwm4 >/dev/null 2>&1; then
    nohup xfwm4 --replace > "$HOME/.vnc/window-manager-display17.log" 2>&1 &
    echo "STARTED=xfwm4 PID=$!"
  elif command -v twm >/dev/null 2>&1; then
    nohup twm > "$HOME/.vnc/window-manager-display17.log" 2>&1 &
    echo "STARTED=twm PID=$!"
  elif command -v fluxbox >/dev/null 2>&1; then
    nohup fluxbox > "$HOME/.vnc/window-manager-display17.log" 2>&1 &
    echo "STARTED=fluxbox PID=$!"
  elif command -v icewm >/dev/null 2>&1; then
    nohup icewm > "$HOME/.vnc/window-manager-display17.log" 2>&1 &
    echo "STARTED=icewm PID=$!"
  else
    echo "NO_WINDOW_MANAGER_FOUND"
  fi
fi

sleep 2
echo "--- status ---"
pgrep -a -u "$USER" -f 'Xvnc :17|openbox|metacity|xfwm4|twm|fluxbox|icewm|mwm|xterm|Novas' || true
echo "--- wm log ---"
tail -30 "$HOME/.vnc/window-manager-display17.log" 2>/dev/null || true
