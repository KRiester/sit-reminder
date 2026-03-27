# sit-reminder

Smart break reminders for macOS. Zero dependencies. Respects your flow.

**Health is not a trade-off for productivity — it's fuel for it.**

## What it does

Detects when you've been sitting too long and reminds you to move — with motivational messages and concrete activity suggestions. Uses only built-in macOS tools (no apps to install, no background processes eating your battery).

```
🦵 Time to move! (42 min sitting)
"A quick walk resets your brain better than coffee."
→ Try: Roll your shoulders: 10 forward, 10 back
```

## How it works

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
- **Smart escalation.** After 4+ ignored reminders, the tone shifts to empathetic and interval increases.
- **Overnight-aware.** Left your laptop on overnight? Silent reset, no annoying dialog.
- **Your click doesn't cheat the system.** Idle time is measured *before* the dialog appears.

See **[FLOW.md](FLOW.md)** for the complete user experience walkthrough.

## Install

Requires macOS. No Homebrew, no Python, no Node — just bash and built-in macOS tools.

```bash
git clone https://github.com/kilianriester/sit-reminder.git
cd sit-reminder
make install
```

The installer asks a few questions:

```
🦵 Sit-Reminder Setup
─────────────────────
Sit limit in minutes [35]: 30
Remind again every X minutes [20]:
Active hours start (0-23) [7]:
Active hours end (0-23) [22]:
Language (en/de) [en]:
Personal reason, e.g. "knee health" (optional) []: knee health

✅ Installed and running!
```

## Configure

Edit `~/.config/sit-reminder/config` anytime. Changes take effect within 2 minutes.

```bash
# ── Timing ──
SIT_LIMIT_MIN=35          # Minutes before first reminder
RENOTIFY_MIN=20           # Minutes between repeated reminders
ACTIVE_HOUR_START=7
ACTIVE_HOUR_END=22

# ── Language ──
LANGUAGE=en               # "en" or "de"

# ── Personal health reason (optional) ──
REASON="knee health"      # Shown in reminders

# ── Break activities ──
# One random activity is suggested per reminder.
ACTIVITIES=(
    "Stand up and stretch for 30 seconds"
    "Walk to the kitchen and get some water"
    "Do 10 squats — your legs will thank you"
    "Roll your shoulders: 10 forward, 10 back"
    # Add your own!
)
```

## Commands

```bash
make install    # Install and start
make uninstall  # Stop and remove
make status     # Is it running? Current session info
make stats      # Today's break statistics
make test       # Send a test notification now
make logs       # Show recent log entries
```

## Resource usage

**Practically zero.** The script runs for ~80ms every 2 minutes, then exits completely. Between checks: no process, no RAM, no CPU, no GPU. `ProcessType: Background` tells macOS to throttle it further when the system is busy.

For comparison: a single Chrome tab uses more resources continuously than this script uses in a full day.

## Files

| Installed to | Purpose |
|---|---|
| `~/.local/bin/sit-reminder.sh` | The script |
| `~/.config/sit-reminder/config` | Your configuration |
| `~/Library/LaunchAgents/com.sit-reminder.plist` | Auto-start every 2 min |
| `~/.local/share/sit-reminder/` | State + logs (auto-created) |

## Advanced config

These settings live in `~/.config/sit-reminder/config` alongside the basic options above.

| Setting | Default | What it does |
|---------|---------|--------------|
| `IDLE_ASK_SEC` | 300 | Seconds of no input before asking "Were you away?" |
| `IDLE_AUTOBREAK_SEC` | 600 | Seconds idle to auto-detect a break (no dialog) |
| `DIALOG_COOLDOWN_SEC` | 1200 | Minimum seconds between idle dialogs |
| `LONG_BREAK_MIN` | 120 | Minutes away before skipping the activity dialog |

## FAQ

**Notifications don't appear**
Check System Settings → Notifications → Script Editor. Notifications must be allowed. Run `make test` to trigger a test notification.

**I left my laptop on overnight — weird dialog in the morning?**
Won't happen. Breaks longer than 2 hours (configurable via `LONG_BREAK_MIN`) skip the activity dialog entirely. You'll just see a friendly "Welcome back! Timer reset." notification.

**How do I change the language?**
Edit `~/.config/sit-reminder/config` and set `LANGUAGE=de` (or `en`). Changes take effect within 2 minutes.

**Can I add my own activities?**
Yes — add lines to the `ACTIVITIES` array in your config. One random activity is shown per reminder.

**How do I temporarily pause it?**
`launchctl unload ~/Library/LaunchAgents/com.sit-reminder.plist` to pause. Run `make install` to restart.

**It reminds me too often / not often enough**
Adjust `SIT_LIMIT_MIN` (first reminder) and `RENOTIFY_MIN` (repeat interval). After 4+ ignored reminders, the interval automatically stretches by 50%.

## Uninstall

```bash
make uninstall
# Config is kept for re-install. To remove it too:
rm -rf ~/.config/sit-reminder
```

## Why

We spend hours at our desks. Fitness trackers remind us, but a notification on your wrist is easy to ignore. A dialog on your screen — right where your attention is — is harder to dismiss.

This started as a personal script for knee rehabilitation. It turned out the combination of idle detection, interactive dialogs, and motivational framing works better than any wearable reminder.

Your body is your primary tool. Keep it running.

## License

MIT
