#!/usr/bin/env bash
cd "$HOME/workspace" || cd "$HOME"
export DISPLAY=:17
export PATH="/tools/synopsys/verdi/W-2024.09-SP2/bin:/tools/synopsys/vcs/W-2024.09-SP1/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
nohup /tools/synopsys/verdi/W-2024.09-SP2/bin/verdi > "$HOME/.vnc/verdi-display17.log" 2>&1 < /dev/null &
echo "VERDI_LAUNCHED_PID=$!"
