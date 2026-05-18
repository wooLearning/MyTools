#!/usr/bin/env bash
set -euo pipefail

DISPLAY_NUM="${1:-17}"
GEOMETRY="${2:-1600x1000}"
DEPTH="${3:-24}"
VNC_PASS="${4:-}"
PORT=$((5900 + DISPLAY_NUM))

mkdir -p "$HOME/.vnc"
chmod 700 "$HOME/.vnc"
if [ -n "$VNC_PASS" ]; then
  printf '%s\n' "$VNC_PASS" | vncpasswd -f > "$HOME/.vnc/passwd"
fi
if [ ! -s "$HOME/.vnc/passwd" ]; then
  echo "VNC password is not configured. Pass it as argument 4 or create $HOME/.vnc/passwd first." >&2
  exit 2
fi
chmod 600 "$HOME/.vnc/passwd"

cat > "$HOME/.vnc/xstartup" <<'EOS'
#!/usr/bin/env bash
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export SHELL=/bin/bash
export PATH=/tools/synopsys/verdi/W-2024.09-SP2/bin:/tools/synopsys/vcs/W-2024.09-SP1/bin:$PATH
[ -r "$HOME/.bashrc" ] && . "$HOME/.bashrc" || true

if command -v gnome-session >/dev/null 2>&1; then
  exec gnome-session
elif command -v startxfce4 >/dev/null 2>&1; then
  exec startxfce4
elif command -v xterm >/dev/null 2>&1; then
  xterm -geometry 120x35+30+30 -title "Remote Verdi Terminal" -e bash -lc 'echo "DISPLAY=$DISPLAY"; echo "Run: verdi"; exec bash' &
  if command -v twm >/dev/null 2>&1; then
    exec twm
  fi
  wait
else
  sleep infinity
fi
EOS
chmod 755 "$HOME/.vnc/xstartup"

if pgrep -u "$USER" -f "Xvnc :${DISPLAY_NUM}\b" >/dev/null 2>&1; then
  echo "VNC_ALREADY_RUNNING display=:${DISPLAY_NUM} port=${PORT}"
  exit 0
fi

vncserver ":${DISPLAY_NUM}" -localhost -geometry "$GEOMETRY" -depth "$DEPTH" -rfbauth "$HOME/.vnc/passwd" || {
  echo "vncserver_failed_trying_Xvnc"
  Xvnc ":${DISPLAY_NUM}" -localhost -SecurityTypes VncAuth -rfbauth "$HOME/.vnc/passwd" -geometry "$GEOMETRY" -depth "$DEPTH" -desktop "remote-verdi" &
  sleep 2
  DISPLAY=":${DISPLAY_NUM}" "$HOME/.vnc/xstartup" > "$HOME/.vnc/xstartup-${DISPLAY_NUM}.log" 2>&1 &
}

sleep 2
if ss -ltn | grep -q ":${PORT} "; then
  echo "VNC_READY display=:${DISPLAY_NUM} port=${PORT}"
else
  echo "VNC_NOT_LISTENING display=:${DISPLAY_NUM} port=${PORT}"
  tail -80 "$HOME/.vnc"/*.log 2>/dev/null || true
  exit 1
fi
