# sit-reminder

Smart break reminders for macOS — with optional Claude Code remote control.

**Your body is your operating system. Everything else runs on top of it.**

## What's in the box

- **sit-reminder** — detects when you've been sitting too long, reminds you to move. Zero dependencies, just bash + macOS.
- **Claude Code Remote Control** — persistent AI session in tmux with auto-restart. Access from your phone via claude.ai. *(optional)*
- **Menu bar widget** — real-time sitting timer + Claude RC controls in your macOS menu bar via SwiftBar. *(optional)*

## Quick start

```bash
git clone https://github.com/kilianriester/sit-reminder.git
cd sit-reminder
make install          # sit-reminder only
make install-rc       # add Claude Code Remote Control (needs tmux + Claude CLI)
make widget           # add menu bar widget (needs SwiftBar)
```

Or install everything at once:

```bash
make install-all
```

## sit-reminder

Detects when you've been sitting too long and reminds you to move — with motivational messages and concrete activity suggestions. Uses only built-in macOS tools.

```
🦵 Time to move! (42 min sitting)
"A quick walk resets your brain better than coffee."
→ Try: Roll your shoulders: 10 forward, 10 back
```

### How it works

```
  ⏰ Checks every 2 min (via launchd)
  │
  ├─ Screen locked or display off?  →  Break detected ✅
  │
  ├─ No keyboard/mouse for 5 min?
  │   ├─ Dialog: "What were you doing?"
  │   │   ├─ "Was away 🚶"  →  Break detected ✅
  │   │   └─ "Was here 📖"  →  Timer keeps running
  │   └─ No response for 10 min  →  Break detected ✅
  │
  └─ Sitting > 35 min?  →  🔔 Reminder!
      └─ Repeats every 20 min until you take a break
```

Key design decisions:
- **Not just a timer.** Detects screen lock, display sleep, and keyboard/mouse activity.
- **Asks, doesn't assume.** When you stop typing, it asks if you were reading or actually away.
- **No spam.** 20-min cooldown between dialogs. Reminders repeat but don't stack.
- **Smart escalation.** After 4+ ignored reminders, the tone shifts and interval increases.
- **Overnight-aware.** Left your laptop on overnight? Silent reset, no annoying dialog.

### Configure

Edit `~/.config/sit-reminder/config` anytime. Changes take effect within 2 minutes.

```bash
SIT_LIMIT_MIN=35          # Minutes before first reminder
RENOTIFY_MIN=20           # Minutes between repeated reminders
ACTIVE_HOUR_START=7
ACTIVE_HOUR_END=22
LANGUAGE=en               # "en" or "de"
REASON="knee health"      # Shown in reminders (optional)
ACTIVITIES=(
    "Stand up and stretch for 30 seconds"
    "Walk to the kitchen and get some water"
    "Do 10 squats — your legs will thank you"
    # Add your own!
)
```

## Claude Code Remote Control

A persistent Claude Code session that survives crashes, disconnects, and long idle periods. Access it from your phone via claude.ai — no scanning, just open the app and prompt.

### Prerequisites

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) (`claude`)
- tmux (`brew install tmux`)

### Install

```bash
make install-rc
```

### Usage

```bash
claude-rc.sh start [project-dir]   # Start (default: $HOME or $CLAUDE_RC_PROJECT)
claude-rc.sh stop                  # Stop gracefully
claude-rc.sh status                # Show status + recent log
claude-rc.sh attach                # Attach to tmux session
```

### How it works

- Runs `claude remote-control` inside a tmux session
- Auto-restarts on crash with exponential backoff (5s → 300s, max 50 retries)
- `caffeinate` prevents Mac sleep while running
- PID tracking prevents duplicate instances
- 7-day log retention with auto-rotation

Set `CLAUDE_RC_PROJECT` environment variable to change the default project directory.

## Menu bar widget

Real-time sitting timer + Claude RC controls in your macOS menu bar via [SwiftBar](https://github.com/swiftbar/SwiftBar).

```
🦵 23m · 3/8            ← sitting time · breaks today
🦵 23m · 3/8 | ◉ RC     ← with Claude RC running
```

### Install

```bash
brew install --cask swiftbar    # if not installed
make widget
```

### What you see

- **Timer** — current sitting time, color-coded (green → yellow → orange → red)
- **Breaks** — progress toward daily goal (X/8)
- **MOVE!** — flashes red when overdue
- **Quick actions** — manual break, pause for 1 hour
- **Claude RC** — start/stop, bridge URL, session attach *(auto-detected, hidden if not installed)*

The widget reads the same state files as the background scripts — no extra processes, no extra resources.

## All commands

```bash
# Sit-Reminder
make install        # Install and start
make uninstall      # Stop and remove
make status         # Check if running
make stats          # Today's break statistics
make test           # Send a test notification
make logs           # Show recent log entries

# Claude Code Remote Control
make install-rc     # Install (requires tmux + Claude CLI)
make uninstall-rc   # Stop and remove
make status-rc      # Check status

# Combined
make install-all    # Install everything + widget
make uninstall-all  # Remove everything
make widget         # Install menu bar widget
make help           # Show all commands
```

## Files

| Installed to | Purpose |
|---|---|
| `~/.local/bin/sit-reminder.sh` | Break reminder script |
| `~/.local/bin/claude-rc.sh` | Remote control manager |
| `~/.local/bin/start-with-terminal.sh` | SwiftBar → Terminal bridge |
| `~/.config/sit-reminder/config` | Your configuration |
| `~/Library/LaunchAgents/com.sit-reminder.plist` | Auto-start every 2 min |
| `~/.local/share/sit-reminder/` | State + logs |
| `~/.claude-rc/` | RC state + logs |

## Resource usage

**Practically zero.** The sit-reminder script runs for ~80ms every 2 minutes, then exits completely. Between checks: no process, no RAM, no CPU. `ProcessType: Background` tells macOS to throttle it further when the system is busy.

Claude RC runs a persistent tmux + claude process. Typical RAM: ~200-400MB. `caffeinate` prevents sleep but uses negligible resources.

## FAQ

**Notifications don't appear**
Check System Settings → Notifications → Script Editor. Run `make test` to trigger a test.

**I left my laptop on overnight — weird dialog?**
Won't happen. Breaks longer than 2 hours skip the activity dialog entirely.

**How do I change the language?**
Set `LANGUAGE=de` (or `en`) in `~/.config/sit-reminder/config`.

**Can I add my own activities?**
Yes — add lines to the `ACTIVITIES` array in your config.

**How do I temporarily pause?**
Click "Pause (1 hour)" in the widget, or run `launchctl unload ~/Library/LaunchAgents/com.sit-reminder.plist`.

**Claude RC won't start**
Check: `command -v tmux` and `command -v claude`. Both must be in your PATH.

**How do I see the bridge URL?**
The SwiftBar widget shows it when RC is running. Or: `tmux attach-session -t claude-rc`.

**Can I change the RC project directory?**
Set `export CLAUDE_RC_PROJECT="/your/path"` before starting, or pass it directly: `claude-rc.sh start /your/path`.

## Uninstall

```bash
make uninstall-all
# Config is kept. To remove it too:
rm -rf ~/.config/sit-reminder
```

## License

MIT
