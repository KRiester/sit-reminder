#!/bin/bash
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>
# <swiftbar.hideSwiftBar>false</swiftbar.hideSwiftBar>
#
# sit-reminder SwiftBar widget
# Real-time sitting timer + daily stats + optional Claude Code Remote Control.
# https://github.com/kilianriester/sit-reminder

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# --- Auto-detect Claude RC ---
CLAUDE_RC_INSTALLED=false
CLAUDE_RC_SCRIPT="$HOME/.local/bin/claude-rc.sh"
if [[ -x "$CLAUDE_RC_SCRIPT" ]]; then
    CLAUDE_RC_INSTALLED=true
    CLAUDE_RC_DIR="$HOME/.claude-rc"
    CLAUDE_RC_PID_FILE="$CLAUDE_RC_DIR/claude-rc.pid"
    CLAUDE_RC_START_SCRIPT="$HOME/.local/bin/start-with-terminal.sh"
    TMUX="$(command -v tmux 2>/dev/null || echo /opt/homebrew/bin/tmux)"
fi

STATE_DIR="$HOME/.local/share/sit-reminder"
STATE_FILE="$STATE_DIR/state"
CONFIG_FILE="$HOME/.config/sit-reminder/config"
LOG_FILE="$STATE_DIR/sit-reminder.log"
PAUSE_FILE="$STATE_DIR/paused_until"

# --- Load config defaults ---
SIT_LIMIT_MIN=35
LANGUAGE=en
REASON=""
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE" 2>/dev/null || true
fi

BREAK_GOAL=8
NOW=$(date +%s)
TODAY=$(date '+%Y-%m-%d')

# --- Handle actions (must run before output) ---
case "${1:-}" in
    --break)
        cat > "$STATE_FILE" <<EOF
last_break_epoch=$NOW
notified_epoch=0
idle_asked_epoch=0
break_pending=0
break_start_epoch=0
last_active_epoch=$NOW
notify_count=0
EOF
        echo "$(date '+%Y-%m-%d %H:%M:%S') BREAK: Manual break via SwiftBar widget" >> "$LOG_FILE"
        exit 0
        ;;
    --pause)
        echo $(( NOW + 3600 )) > "$PAUSE_FILE"
        echo "$(date '+%Y-%m-%d %H:%M:%S') PAUSE: Paused for 1 hour via SwiftBar widget" >> "$LOG_FILE"
        exit 0
        ;;
    --resume)
        rm -f "$PAUSE_FILE"
        echo "$(date '+%Y-%m-%d %H:%M:%S') RESUME: Resumed via SwiftBar widget" >> "$LOG_FILE"
        exit 0
        ;;
    --rc-start)
        if $CLAUDE_RC_INSTALLED; then
            "$CLAUDE_RC_START_SCRIPT" &
        fi
        exit 0
        ;;
    --rc-stop)
        if $CLAUDE_RC_INSTALLED; then
            "$CLAUDE_RC_SCRIPT" stop >/dev/null 2>&1
        fi
        exit 0
        ;;
esac

# --- Read state ---
last_break_epoch=$NOW
notified_epoch=0
notify_count=0
if [[ -f "$STATE_FILE" ]]; then
    source "$STATE_FILE" 2>/dev/null || true
fi

sitting_sec=$(( NOW - last_break_epoch ))
sitting_min=$(( sitting_sec / 60 ))

# --- Check pause ---
is_paused=false
pause_remaining=""
if [[ -f "$PAUSE_FILE" ]]; then
    paused_until=$(cat "$PAUSE_FILE" 2>/dev/null)
    if [[ "$NOW" -lt "$paused_until" ]]; then
        is_paused=true
        pause_min=$(( (paused_until - NOW) / 60 ))
        pause_remaining="${pause_min}m"
    fi
fi

# --- Today's stats from log ---
breaks_today=0
activities_today=""
notifs_today=0
checks_today=0
longest_today=0
if [[ -f "$LOG_FILE" ]]; then
    todays_log=$(grep "^$TODAY" "$LOG_FILE" 2>/dev/null)
    breaks_today=$(echo "$todays_log" | grep "BREAK:" | grep -v "Auto-break" | wc -l | tr -d ' ')
    notifs_today=$(echo "$todays_log" | grep "NOTIFY:" | wc -l | tr -d ' ')
    checks_today=$(echo "$todays_log" | grep "CHECK:" | wc -l | tr -d ' ')
    longest_today=$(echo "$todays_log" | grep "CHECK:" | sed -n 's/.*Sitting \([0-9]*\) min.*/\1/p' | sort -n | tail -1 2>/dev/null)
    longest_today=${longest_today:-0}
    activities_today=$(echo "$todays_log" | grep "ACTIVITY:" | sed 's/.*ACTIVITY: //' 2>/dev/null)
fi

active_hours=$(( checks_today * 2 ))
active_h=$(( active_hours / 60 ))
active_m=$(( active_hours % 60 ))

# --- Check Claude RC status ---
claude_rc_running=false
claude_rc_pid=""
claude_rc_ram="-"
if $CLAUDE_RC_INSTALLED && [[ -f "$CLAUDE_RC_PID_FILE" ]]; then
    claude_rc_pid=$(cat "$CLAUDE_RC_PID_FILE" 2>/dev/null)
    if [[ -n "$claude_rc_pid" ]] && kill -0 "$claude_rc_pid" 2>/dev/null; then
        claude_rc_running=true
        claude_rc_ram=$(ps -eo rss,comm 2>/dev/null | grep -E "claude|tmux" | grep -v grep | awk '{sum+=$1} END {printf "%.0f", sum/1024}')
        claude_rc_ram="${claude_rc_ram}MB"
    fi
fi

# --- Menu bar line ---
rc_suffix=""
if $claude_rc_running; then
    rc_suffix=" | ◉ RC"
fi

if $is_paused; then
    echo "🦵 ⏸ ${pause_remaining}${rc_suffix} | color=#8E8E93"
elif [[ "$sitting_min" -ge $(( SIT_LIMIT_MIN + 15 )) ]]; then
    echo "🦵 MOVE! · ${breaks_today}/${BREAK_GOAL}${rc_suffix} | color=#FF3B30 sfimage=figure.walk"
elif [[ "$sitting_min" -ge "$SIT_LIMIT_MIN" ]]; then
    echo "🦵 ${sitting_min}m · ${breaks_today}/${BREAK_GOAL}${rc_suffix} | color=#FF9500"
elif [[ "$sitting_min" -ge $(( SIT_LIMIT_MIN * 2 / 3 )) ]]; then
    echo "🦵 ${sitting_min}m · ${breaks_today}/${BREAK_GOAL}${rc_suffix} | color=#FFD60A"
else
    echo "🦵 ${sitting_min}m · ${breaks_today}/${BREAK_GOAL}${rc_suffix} | color=#34C759"
fi

echo "---"

# --- Status section ---
echo "Status | size=14"
echo "  Sitting: ${sitting_min} min | size=12"
remaining=$(( SIT_LIMIT_MIN - sitting_min ))
if [[ "$remaining" -gt 0 && "$is_paused" == "false" ]]; then
    echo "  Next reminder in: ${remaining} min | size=12"
elif [[ "$is_paused" == "true" ]]; then
    echo "  Paused for ${pause_remaining} | size=12 color=#8E8E93"
else
    overdue=$(( sitting_min - SIT_LIMIT_MIN ))
    echo "  ${overdue} min overdue! | size=12 color=#FF3B30"
fi
if [[ -n "$REASON" ]]; then
    echo "  Reason: $REASON | size=11 color=#8E8E93"
fi
echo "---"

# --- Today section ---
echo "Today | size=14"
echo "  Breaks: ${breaks_today}/${BREAK_GOAL} | size=12"
echo "  Active: ~${active_h}h ${active_m}m | size=12"
echo "  Longest session: ${longest_today} min | size=12"
echo "  Reminders sent: ${notifs_today} | size=12"

if [[ -n "$activities_today" ]]; then
    filtered_acts=$(echo "$activities_today" | grep -v "long_break\|Long break\|skipped" | sort -u | grep -v '^$')
    if [[ -n "$filtered_acts" ]]; then
        echo "---"
        echo "Activities | size=14"
        echo "$filtered_acts" | while read -r act; do
            echo "  $act | size=12 color=#34C759"
        done
    fi
fi
echo "---"

# --- Motivation ---
if [[ "$breaks_today" -ge 6 ]]; then
    echo "Outstanding! Your body thanks you. | size=11 color=#34C759"
elif [[ "$breaks_today" -ge 3 ]]; then
    echo "Solid day! Keep going. | size=11 color=#34C759"
elif [[ "$breaks_today" -ge 1 ]]; then
    echo "Good start. Keep moving! | size=11 color=#FFD60A"
elif [[ "$notifs_today" -gt 0 ]]; then
    echo "Reminders sent but no breaks yet. | size=11 color=#FF9500"
fi
echo "---"

# --- Actions ---
if $is_paused; then
    echo "▶ Resume | bash=$0 param1=--resume terminal=false refresh=true color=#34C759 size=13"
else
    echo "🚶 I just took a break | bash=$0 param1=--break terminal=false refresh=true color=#34C759 size=13"
    echo "⏸ Pause (1 hour) | bash=$0 param1=--pause terminal=false refresh=true size=12"
fi

# --- Claude RC section (only if installed) ---
if $CLAUDE_RC_INSTALLED; then
    echo "---"
    if $claude_rc_running; then
        echo "Claude Remote Control | color=#34C759 size=14"
        echo "  Running (PID $claude_rc_pid) · $claude_rc_ram | size=12"
        bridge_url=$("$TMUX" capture-pane -t claude-rc -p 2>/dev/null | grep -o 'https://claude.ai/code?bridge=[^ ]*' | tail -1)
        if [[ -n "$bridge_url" ]]; then
            echo "  Open in Browser | href=$bridge_url size=12"
        fi
        echo "  ⏹ Stop Remote Control | bash=$0 param1=--rc-stop terminal=false refresh=true color=#FF3B30 size=12"
        echo "  Attach Session | bash=$TMUX param1=attach-session param2=-t param3=claude-rc terminal=true size=12"
    else
        echo "Claude Remote Control | color=#FF3B30 size=14"
        echo "  Stopped | size=12"
        echo "  ▶ Start Remote Control | bash=$0 param1=--rc-start terminal=false refresh=true color=#34C759 size=13"
    fi
fi

echo "---"
echo "Open Config | bash=/usr/bin/open param1=$CONFIG_FILE terminal=false size=12"
echo "Open Logs | bash=/usr/bin/open param1=$STATE_DIR terminal=false size=12"
echo "🔄 Refresh | refresh=true size=12"
