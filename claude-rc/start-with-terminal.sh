#!/bin/bash
# Opens a Terminal window attached to the claude-rc tmux session.
# Called by SwiftBar widget — starts claude-rc if not already running.

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

CLAUDE_RC="$HOME/.local/bin/claude-rc.sh"
TMUX="$(command -v tmux 2>/dev/null || echo /opt/homebrew/bin/tmux)"

# Start claude-rc in background if not already running
if [[ -f "$HOME/.claude-rc/claude-rc.pid" ]]; then
    pid=$(cat "$HOME/.claude-rc/claude-rc.pid" 2>/dev/null)
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        # Already running — just attach
        osascript -e "tell application \"Terminal\"
            activate
            do script \"$TMUX attach-session -t claude-rc\"
        end tell"
        exit 0
    fi
fi

# Start fresh
"$CLAUDE_RC" start &
sleep 4

# Open Terminal attached to tmux session
osascript -e "tell application \"Terminal\"
    activate
    do script \"$TMUX attach-session -t claude-rc\"
end tell"
