# Sit-Reminder: Complete UX Flow

How every user-facing moment works — from install to daily use.

---

## 1. Installation

```
$ make install

  🦵 Sit-Reminder Setup
  ─────────────────────

  Sit limit in minutes [35]:
  Remind again every X minutes [20]:
  Active hours start (0-23) [7]:
  Active hours end (0-23) [22]:
  Language (en/de) [en]: de
  Personal reason, e.g. "knee health" (optional) []: knee health

  Created config: ~/.config/sit-reminder/config

  ✅ Installed and running!

  Config:  ~/.config/sit-reminder/config
  Script:  ~/.local/bin/sit-reminder.sh
  Logs:    ~/.local/share/sit-reminder/sit-reminder.log

  Tip: Edit the config anytime — changes take effect within 2 minutes.
  Run 'make test' to see a test notification now.
```

What happens: The script starts checking every 2 minutes via launchd. No app, no menu bar icon, no daemon — just a lightweight background check.

---

## 2. A typical workday

### 08:00 — You sit down

The timer starts silently. No notification, no interruption.

```
LOG: CHECK: Sitting 0 min, idle 0s
```

### 08:35 — First reminder (35 min sitting)

A macOS notification appears with sound:

```
┌─────────────────────────────────────────────┐
│ 🦵 Time to move! (knee health)              │
│ 35 min sitting                              │
│                                             │
│ "Your best ideas happen when your body      │
│  moves." → Stand up and stretch for 30s     │
└─────────────────────────────────────────────┘
```

- Random motivational message (10 options)
- Random activity suggestion (10 options)
- Your personal reason shown in the title

### 08:40 — You stop typing (reading code)

After 5 minutes of no keyboard/mouse:

```
┌──────────────────────────────────────────────┐
│  🦵 Movement check                           │
│                                              │
│  You've been sitting for 40 min (knee        │
│  health) — time to move!                     │
│                                              │
│  No keyboard/mouse for 5 min.                │
│  What were you doing?                        │
│                                              │
│            [Was away 🚶]  [Was here 📖]       │
└──────────────────────────────────────────────┘
```

- **"Was here"** → Timer continues, won't re-ask for 20 min
- **"Was away"** → Break detected, timer resets
- **No response (5 min)** → Assumes you left, auto-break

### 08:55 — Second reminder (20 min later, still sitting)

```
┌─────────────────────────────────────────────┐
│ 🦵 Time to move! (knee health)              │
│ 55 min sitting                              │
│                                             │
│ "5 min now = sharper focus for the next      │
│  hour." → Do 10 squats — your legs will     │
│  thank you                                  │
└─────────────────────────────────────────────┘
```

### 09:00 — You take a break (lock screen, walk away)

Break is auto-detected via screen lock or display sleep.

```
LOG: BREAK: Screen locked or display off
```

No notification, no dialog. Silent.

### 09:05 — You come back

When you start typing again:

```
┌──────────────────────────────────────────────┐
│  🦵 Welcome back!                            │
│                                              │
│  What did you do during your break (5 min)?  │
│                                              │
│  ○ Stretched / Mobility                      │
│  ○ Squats / Leg work                         │
│  ○ Walked around                             │
│  ○ Got water                                 │
│  ○ Eye break (looked outside)                │
│  ○ Shoulder / Neck rolls                     │
│  ○ Meeting / Call                            │
│  ○ Lunch / Meal                              │
│  ● Just stood up briefly                     │
│                                              │
│              [Cancel]  [OK]                  │
└──────────────────────────────────────────────┘
```

- Shows how long the break was
- 9 activity options (exercise + non-exercise)
- Logged for daily stats
- Timer resets to 0

### 09:05 — New cycle begins

Fresh 35-minute countdown starts.

---

## 3. Edge cases

### Long sitting — escalation

After 4+ reminders (75+ minutes sitting), the tone shifts:

```
Reminder 1-3 (every 20 min):
  "Your body is your primary tool. Keep it running."
  → Normal motivational message + activity

Reminder 4+ (every 30 min):
  "Your body is asking gently. Just 2 min is enough."
  → Empathetic, shorter interval increase
```

The escalation is compassionate, not shaming. Interval stretches from 20 to 30 minutes to reduce fatigue.

### Overnight / long absence (> 2 hours away)

When you left your laptop on overnight and come back:

```
┌─────────────────────────────────────────────┐
│ ☀️ Welcome back!                             │
│ Break: 10h 2m                               │
│                                             │
│ Timer reset. Let's have a healthy day!       │
└─────────────────────────────────────────────┘
```

- **No dialog** — doesn't ask "what did you do" for 10-hour breaks
- Just a friendly notification with the break duration
- Timer resets silently
- Threshold: 2 hours (configurable via `LONG_BREAK_MIN`)

### Meeting / lunch break (30 min - 2 hours)

You step away for a meeting and come back after 45 minutes:

```
┌──────────────────────────────────────────────┐
│  🦵 Welcome back!                            │
│                                              │
│  What did you do during your break (45 min)? │
│                                              │
│  ○ Stretched / Mobility                      │
│  ...                                         │
│  ○ Meeting / Call          ← relevant!       │
│  ○ Lunch / Meal            ← relevant!       │
│  ● Just stood up briefly                     │
│                                              │
│              [Cancel]  [OK]                  │
└──────────────────────────────────────────────┘
```

Non-exercise options (Meeting, Lunch) ensure you always have a fitting choice.

### Outside active hours

Between 10 PM and 7 AM (default): script exits silently. No notifications, no dialogs, no logging.

### Time jump (sleep / restart)

If sitting time exceeds 4 hours and you're idle: auto-break. Catches system sleep and restarts without user intervention.

---

## 4. Daily stats

```
$ make stats

  📊 Today's Stats (2026-03-27)
  ─────────────────────────────
  Breaks taken:       6
  Activities logged:  5
  Reminders sent:     8
  Time at computer:   ~5h 12m
  Longest session:    42 min

  Today's activities:
    ✅ Stretched / Mobility
    ✅ Walked around
    ✅ Got water
    ✅ Squats / Leg work
    ✅ Meeting / Call

  🏆 Outstanding! 6 breaks — your body thanks you.
```

Motivation tiers:
- **6+ breaks:** 🏆 "Outstanding! Your body thanks you."
- **3-5 breaks:** 💪 "Solid day! Keep going."
- **1-2 breaks:** 🦵 "Good start. Keep moving!"
- **0 breaks but reminders:** ⚠️ "Reminders sent but no breaks yet."

---

## 5. All notifications at a glance

| Trigger | Type | Content |
|---------|------|---------|
| 35 min sitting | Notification | Motivational message + activity suggestion |
| 55 min sitting | Notification | Same format, different message |
| 75+ min sitting | Notification | Empathetic escalation: "Your body is asking gently" |
| 5 min idle | Dialog | "Was away / Was here" (2 buttons) |
| Return from short break | Dialog | "What did you do?" (9 options) |
| Return from long break | Notification | "Welcome back! Timer reset." |
| No dialog response | Auto | Silent break detection |
| Screen lock | Auto | Silent break detection |

---

## 6. Configuration reference

| Setting | Default | Description |
|---------|---------|-------------|
| `SIT_LIMIT_MIN` | 35 | Minutes before first reminder |
| `RENOTIFY_MIN` | 20 | Minutes between reminders |
| `ACTIVE_HOUR_START` | 7 | Active hours start (24h) |
| `ACTIVE_HOUR_END` | 22 | Active hours end (24h) |
| `LANGUAGE` | en | `en` or `de` |
| `REASON` | (empty) | Personal reason shown in reminders |
| `ACTIVITIES` | (10 built-in) | Custom activity suggestions |
| `IDLE_ASK_SEC` | 300 | Seconds idle before asking dialog |
| `IDLE_AUTOBREAK_SEC` | 600 | Seconds idle for auto-break |
| `DIALOG_COOLDOWN_SEC` | 1200 | Seconds between dialog re-asks |
| `LONG_BREAK_MIN` | 120 | Minutes away before skipping activity dialog |

Edit `~/.config/sit-reminder/config` — changes take effect within 2 minutes.
