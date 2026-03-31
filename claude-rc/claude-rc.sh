#!/bin/bash
# claude-rc.sh — Persistent Claude Code Remote Control
# Manages a tmux session with auto-restart, exponential backoff, and caffeinate.
# Usage: claude-rc.sh [start|stop|status|attach|help] [project-dir]

set -euo pipefail

# --- Configuration ---
SESSION_NAME="claude-rc"
RC_DIR="$HOME/.claude-rc"
LOG_DIR="$RC_DIR/logs"
PID_FILE="$RC_DIR/claude-rc.pid"
CAFF_PID_FILE="$RC_DIR/caffeinate.pid"
LOG_FILE="$LOG_DIR/claude-rc.log"
DEFAULT_PROJECT="${CLAUDE_RC_PROJECT:-$HOME}"
MAX_RETRIES=50
BACKOFF_START=5
BACKOFF_MAX=300
LOG_RETENTION_DAYS=7

# --- Resolve binaries ---
TMUX="$(command -v tmux 2>/dev/null || true)"
if [[ -z "$TMUX" ]]; then
    echo "Error: tmux not found. Install with: brew install tmux"
    exit 1
fi

CLAUDE="$(command -v claude 2>/dev/null || true)"
if [[ -z "$CLAUDE" ]]; then
    echo "Error: Claude Code CLI not found. Install from: https://docs.anthropic.com/en/docs/claude-code"
    exit 1
fi

# --- Helpers ---
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

cleanup_old_logs() {
    find "$LOG_DIR" -name "*.log" -mtime +$LOG_RETENTION_DAYS -delete 2>/dev/null || true
}

write_pid() {
    echo $$ > "$PID_FILE"
}

cleanup() {
    log "Cleanup triggered (signal received)"
    # Kill caffeinate if we started it
    if [[ -f "$CAFF_PID_FILE" ]]; then
        local caff_pid
        caff_pid=$(cat "$CAFF_PID_FILE" 2>/dev/null)
        if [[ -n "$caff_pid" ]] && kill -0 "$caff_pid" 2>/dev/null; then
            kill "$caff_pid" 2>/dev/null || true
            log "Killed caffeinate (PID $caff_pid)"
        fi
        rm -f "$CAFF_PID_FILE"
    fi
    rm -f "$PID_FILE"
}

is_running() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE" 2>/dev/null)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

session_exists() {
    "$TMUX" has-session -t "$SESSION_NAME" 2>/dev/null
}

# --- Subcommands ---
cmd_status() {
    echo "=== Claude Remote Control Status ==="
    echo ""

    # Main process
    if is_running; then
        local pid
        pid=$(cat "$PID_FILE")
        echo "Main process:  RUNNING (PID $pid)"
    else
        echo "Main process:  STOPPED"
    fi

    # Caffeinate
    if [[ -f "$CAFF_PID_FILE" ]]; then
        local caff_pid
        caff_pid=$(cat "$CAFF_PID_FILE" 2>/dev/null)
        if [[ -n "$caff_pid" ]] && kill -0 "$caff_pid" 2>/dev/null; then
            echo "Caffeinate:    RUNNING (PID $caff_pid)"
        else
            echo "Caffeinate:    STALE PID FILE"
        fi
    else
        echo "Caffeinate:    NOT RUNNING"
    fi

    # tmux session
    if session_exists; then
        echo "tmux session:  ACTIVE ($SESSION_NAME)"
    else
        echo "tmux session:  NONE"
    fi

    # Claude processes
    local claude_count
    claude_count=$(pgrep -f "claude remote-control" 2>/dev/null | wc -l | tr -d ' ')
    echo "Claude procs:  $claude_count"

    # Last log lines
    echo ""
    echo "=== Recent Log ==="
    tail -5 "$LOG_FILE" 2>/dev/null || echo "(no log file)"
}

cmd_stop() {
    log "Stop requested"

    # Kill main process
    if is_running; then
        local pid
        pid=$(cat "$PID_FILE")
        kill "$pid" 2>/dev/null || true
        log "Sent TERM to main process (PID $pid)"
        sleep 1
    fi

    # Kill caffeinate
    if [[ -f "$CAFF_PID_FILE" ]]; then
        local caff_pid
        caff_pid=$(cat "$CAFF_PID_FILE" 2>/dev/null)
        if [[ -n "$caff_pid" ]] && kill -0 "$caff_pid" 2>/dev/null; then
            kill "$caff_pid" 2>/dev/null || true
        fi
        rm -f "$CAFF_PID_FILE"
    fi

    # Kill any remaining claude remote-control processes in the tmux session
    if session_exists; then
        "$TMUX" send-keys -t "$SESSION_NAME" C-c 2>/dev/null || true
        sleep 1
        pgrep -f "claude remote-control" 2>/dev/null | xargs kill 2>/dev/null || true
    fi

    rm -f "$PID_FILE"
    echo "Claude RC stopped."
    log "Stop complete"
}

cmd_attach() {
    if session_exists; then
        exec "$TMUX" attach-session -t "$SESSION_NAME"
    else
        echo "No tmux session '$SESSION_NAME' found."
        exit 1
    fi
}

cmd_help() {
    cat <<HELP
claude-rc.sh — Persistent Claude Code Remote Control

Usage: claude-rc.sh [command] [project-dir]

Commands:
  start [dir]   Start remote control (default: \$CLAUDE_RC_PROJECT or \$HOME)
  stop          Stop all components gracefully
  status        Show current status
  attach        Attach to tmux session
  help          Show this help

Environment:
  CLAUDE_RC_PROJECT   Default project directory (optional)

The script creates a tmux session, starts 'claude remote-control' inside it,
and auto-restarts on crash with exponential backoff (${BACKOFF_START}s to ${BACKOFF_MAX}s).
caffeinate prevents sleep while running. Max ${MAX_RETRIES} retries before giving up.

Files:
  ~/.claude-rc/logs/           Log files (${LOG_RETENTION_DAYS}-day retention)
  ~/.claude-rc/claude-rc.pid   Main process PID
  ~/.claude-rc/caffeinate.pid  caffeinate PID
HELP
}

cmd_start() {
    local project_dir="${1:-$DEFAULT_PROJECT}"

    # Check if already running
    if is_running; then
        echo "Already running (PID $(cat "$PID_FILE")). Use 'stop' first."
        exit 1
    fi

    # Verify project dir exists
    if [[ ! -d "$project_dir" ]]; then
        echo "Error: Project directory does not exist: $project_dir"
        exit 1
    fi

    # Setup
    mkdir -p "$LOG_DIR"
    cleanup_old_logs

    # Rotate log if > 10MB
    if [[ -f "$LOG_FILE" ]] && [[ $(stat -f%z "$LOG_FILE" 2>/dev/null || echo 0) -gt 10485760 ]]; then
        mv "$LOG_FILE" "$LOG_FILE.$(date '+%Y%m%d-%H%M%S')"
    fi

    write_pid
    trap cleanup EXIT INT TERM

    log "========================================="
    log "Claude RC starting"
    log "Project dir: $project_dir"
    log "PID: $$"
    log "========================================="

    # Start caffeinate bound to our PID
    caffeinate -i -s -w $$ &
    local caff_pid=$!
    echo "$caff_pid" > "$CAFF_PID_FILE"
    log "caffeinate started (PID $caff_pid), bound to our PID $$"

    # Create or reuse tmux session
    if ! session_exists; then
        "$TMUX" new-session -d -s "$SESSION_NAME" -c "$project_dir"
        log "Created tmux session '$SESSION_NAME'"
    else
        log "Reusing existing tmux session '$SESSION_NAME'"
    fi

    # Main restart loop
    local retries=0
    local backoff=$BACKOFF_START

    while [[ $retries -lt $MAX_RETRIES ]]; do
        retries=$((retries + 1))
        log "Starting claude remote-control (attempt $retries/$MAX_RETRIES, backoff ${backoff}s)"

        # Send the command to the tmux session
        "$TMUX" send-keys -t "$SESSION_NAME" "cd '${project_dir}' && '$CLAUDE' remote-control" Enter

        # Wait for the claude process to appear, then monitor it
        sleep 3
        local claude_pid=""

        # Find the claude remote-control process
        for i in $(seq 1 10); do
            claude_pid=$(pgrep -f "claude remote-control" 2>/dev/null | head -1 || true)
            if [[ -n "$claude_pid" ]]; then
                break
            fi
            sleep 1
        done

        if [[ -z "$claude_pid" ]]; then
            log "WARNING: claude process did not start within 10s"
        else
            log "claude running (PID $claude_pid)"

            # Reset backoff on successful start
            backoff=$BACKOFF_START

            # Monitor: wait for claude process to exit
            while kill -0 "$claude_pid" 2>/dev/null; do
                sleep 5
            done

            log "claude process (PID $claude_pid) exited"
        fi

        # Check if tmux session still exists
        if ! session_exists; then
            log "tmux session gone — recreating"
            "$TMUX" new-session -d -s "$SESSION_NAME" -c "$project_dir"
        fi

        # Exponential backoff
        log "Waiting ${backoff}s before restart..."
        sleep "$backoff"

        # Increase backoff (cap at BACKOFF_MAX)
        backoff=$((backoff * 2))
        if [[ $backoff -gt $BACKOFF_MAX ]]; then
            backoff=$BACKOFF_MAX
        fi
    done

    log "ERROR: Max retries ($MAX_RETRIES) reached. Giving up."
    log "Run 'claude-rc.sh start' to restart manually."
    exit 1
}

# --- Main ---
mkdir -p "$LOG_DIR"

case "${1:-start}" in
    start)   cmd_start "${2:-}" ;;
    stop)    cmd_stop ;;
    status)  cmd_status ;;
    attach)  cmd_attach ;;
    help|-h|--help) cmd_help ;;
    *)
        echo "Unknown command: $1"
        cmd_help
        exit 1
        ;;
esac
