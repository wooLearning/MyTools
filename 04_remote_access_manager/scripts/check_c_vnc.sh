#!/usr/bin/env bash
set -u
echo "HOST=$(hostname)"
echo "USER=$(whoami)"
for c in vncserver tigervncserver Xvnc x0vncserver vncpasswd verdi; do
  printf "%s=" "$c"
  command -v "$c" || true
done
echo "--- VNC/Verdi processes ---"
ps -ef | grep -Ei 'vnc|Xvnc|verdi' | grep -v grep || true
echo "--- ~/verdi_vnc_toolkit ---"
ls -la "$HOME/verdi_vnc_toolkit" 2>/dev/null | head -80 || true
echo "--- ~/.vnc ---"
ls -la "$HOME/.vnc" 2>/dev/null | head -80 || true
