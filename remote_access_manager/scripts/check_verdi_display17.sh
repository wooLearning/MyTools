#!/usr/bin/env bash
echo "--- processes ---"
ps -fu "$USER" | grep -E 'Xvnc :17|verdi|Novas' | grep -v grep || true
echo "--- VNC listen ---"
ss -ltn | grep 5917 || true
echo "--- Verdi log ---"
tail -80 "$HOME/.vnc/verdi-display17.log" 2>/dev/null || true
