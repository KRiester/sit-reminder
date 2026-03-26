#!/bin/bash
set -euo pipefail

# ============================================================
# Sit-Reminder: Smart break reminders for macOS
#
# Detects continuous sitting via keyboard/mouse idle time,
# screen lock, and display sleep. Reminds you to move with
# motivational notifications and interactive dialogs.
#
# Zero dependencies. Runs every 2 min via launchd.
# Config: ~/.config/sit-reminder/config
#
# https://github.com/kilianriester/sit-reminder
# ============================================================

# === Load config (or use defaults) ===
CONFIG_DIR="$HOME/.config/sit-reminder"
CONFIG_FILE="$CONFIG_DIR/config"

# Source config if it exists
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE" 2>/dev/null || true
fi

# Apply defaults for anything not set in config
SIT_LIMIT_MIN=${SIT_LIMIT_MIN:-35}
RENOTIFY_MIN=${RENOTIFY_MIN:-20}
ACTIVE_HOUR_START=${ACTIVE_HOUR_START:-7}
ACTIVE_HOUR_END=${ACTIVE_HOUR_END:-22}
LANGUAGE=${LANGUAGE:-en}
REASON=${REASON:-""}

# Derived values (seconds)
SIT_LIMIT_SEC=$(( SIT_LIMIT_MIN * 60 ))
RENOTIFY_SEC=$(( RENOTIFY_MIN * 60 ))
IDLE_ASK_SEC=${IDLE_ASK_SEC:-300}
IDLE_AUTOBREAK_SEC=${IDLE_AUTOBREAK_SEC:-600}
DIALOG_COOLDOWN_SEC=${DIALOG_COOLDOWN_SEC:-1200}

# Default activities if not set in config
if [[ -z "${ACTIVITIES+x}" ]] || [[ ${#ACTIVITIES[@]} -eq 0 ]]; then
    if [[ "$LANGUAGE" == "de" ]]; then
        ACTIVITIES=(
            "Steh auf und streck dich 30 Sekunden"
            "Hol dir ein Glas Wasser"
            "10 Kniebeugen — deine Beine danken es dir"
            "Schultern kreisen: 10x vorwaerts, 10x rueckwaerts"
            "Schau 20 Sekunden aus dem Fenster (Augen brauchen Pausen)"
            "Zehenspitzen beruehren, dann zur Decke strecken"
            "Eine kurze Runde durch den Raum"
            "Sanfte Kniebeugen — 10 pro Seite"
            "Hueftbeuger dehnen — 30 Sekunden pro Seite"
            "Handgelenke kreisen — 10x in jede Richtung"
        )
    else
        ACTIVITIES=(
            "Stand up and stretch for 30 seconds"
            "Walk to the kitchen and get some water"
            "Do 10 squats — your legs will thank you"
            "Roll your shoulders: 10 forward, 10 back"
            "Look out the window for 20 seconds (eyes need breaks too)"
            "Touch your toes, then reach for the ceiling"
            "Take a short walk around the room"
            "Do some gentle knee bends"
            "Stretch your hip flexors (30s each side)"
            "Circle your wrists — 10 times each direction"
        )
    fi
fi

# Paths
STATE_DIR="$HOME/.local/share/sit-reminder"
STATE_FILE="$STATE_DIR/state"
LOG_FILE="$STATE_DIR/sit-reminder.log"

# === Messages by language ===

get_motivational_message() {
    local messages_en=(
        "Movement is not a break from work — it's fuel for it."
        "Your best ideas happen when your body moves."
        "5 min now = sharper focus for the next hour."
        "Sitting is the new smoking. You know what to do."
        "Your body is your primary tool. Keep it running."
        "A quick walk resets your brain better than coffee."
        "Creativity flows when blood flows."
        "Your future self will thank you for this break."
        "Small moves now prevent big problems later."
        "The best code is written by people who move."
    )
    local messages_de=(
        "Bewegung ist keine Pause von der Arbeit — sie ist Treibstoff."
        "Deine besten Ideen kommen, wenn dein Koerper sich bewegt."
        "5 Min jetzt = schaerferer Fokus fuer die naechste Stunde."
        "Sitzen ist das neue Rauchen. Du weisst was zu tun ist."
        "Dein Koerper ist dein wichtigstes Werkzeug. Halt ihn am Laufen."
        "Ein kurzer Spaziergang resettet dein Gehirn besser als Kaffee."
        "Kreativitaet fliesst, wenn Blut fliesst."
        "Dein zukuenftiges Ich wird dir fuer diese Pause danken."
        "Kleine Bewegungen jetzt verhindern grosse Probleme spaeter."
        "Der beste Code wird von Menschen geschrieben, die sich bewegen."
    )

    if [[ "$LANGUAGE" == "de" ]]; then
        local msgs=("${messages_de[@]}")
    else
        local msgs=("${messages_en[@]}")
    fi

    local idx=$(( RANDOM % ${#msgs[@]} ))
    echo "${msgs[$idx]}"
}

get_random_activity() {
    local idx=$(( RANDOM % ${#ACTIVITIES[@]} ))
    echo "${ACTIVITIES[$idx]}"
}

# === Utility functions ===

log_msg() {
    if [[ -f "$LOG_FILE" ]]; then
        tail -n 500 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

get_idle_seconds() {
    local idle_ns
    idle_ns=$(ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {gsub(/[^0-9]/, "", $NF); print $NF; exit}')
    if [[ -z "$idle_ns" || "$idle_ns" == "0" ]]; then
        echo "0"
    else
        echo $((idle_ns / 1000000000))
    fi
}

is_screen_locked() {
    local locked_count
    locked_count=$(ioreg -n Root -d1 -a 2>/dev/null | grep -c "CGSSessionScreenIsLocked" || true)
    [[ "$locked_count" -gt 0 ]]
}

is_display_off() {
    local power_state
    power_state=$(ioreg -n IODisplayWrangler 2>/dev/null \
        | awk '/CurrentPowerState/ {print $NF; exit}')
    [[ -n "$power_state" && "$power_state" -lt 4 ]]
}

is_within_active_hours() {
    local current_hour
    current_hour=$(date +%H)
    current_hour=$((10#$current_hour))
    [[ "$current_hour" -ge "$ACTIVE_HOUR_START" && "$current_hour" -lt "$ACTIVE_HOUR_END" ]]
}

# === State management ===

read_state() {
    if [[ -f "$STATE_FILE" ]]; then
        source "$STATE_FILE" 2>/dev/null || true
        if ! [[ "${last_break_epoch:-}" =~ ^[0-9]+$ ]]; then
            last_break_epoch=$(date +%s)
            notified_epoch=0
            idle_asked_epoch=0
            write_state
            log_msg "REPAIR: State file repaired"
        fi
        # Migration from v1 (notified=0/1 → notified_epoch)
        if [[ "${notified:-}" =~ ^[01]$ ]]; then
            notified_epoch=0
            unset notified 2>/dev/null || true
            write_state
        fi
    else
        last_break_epoch=$(date +%s)
        notified_epoch=0
        idle_asked_epoch=0
        write_state
        log_msg "INIT: State file created"
    fi
}

write_state() {
    mkdir -p "$STATE_DIR"
    cat > "$STATE_FILE" <<STATEEOF
last_break_epoch=${last_break_epoch}
notified_epoch=${notified_epoch:-0}
idle_asked_epoch=${idle_asked_epoch:-0}
break_pending=${break_pending:-0}
STATEEOF
}

do_break() {
    last_break_epoch=$(date +%s)
    notified_epoch=0
    idle_asked_epoch=0
    break_pending=1
    write_state
    log_msg "BREAK: $1"
}

# === Break activity confirmation ===
# When user returns from a break, ask what they did.
# Logged as ACTIVITY for stats tracking.

ask_break_activity() {
    local result

    if [[ "$LANGUAGE" == "de" ]]; then
        result=$(osascript <<'APPLESCRIPT'
set activities to {"Gedehnt / Gestreckt", "Kniebeugen / Beine mobilisiert", "Spaziert / Herumgelaufen", "Wasser geholt", "Augen entspannt (Fensterblick)", "Schultern / Nacken gelockert", "Nur kurz aufgestanden"}
set theChoice to choose from list activities with title "🦵 Willkommen zurueck!" with prompt "Was hast du in der Pause gemacht?" default items {"Nur kurz aufgestanden"}
if theChoice is false then
    return "skipped"
else
    return item 1 of theChoice
end if
APPLESCRIPT
        ) || true
    else
        result=$(osascript <<'APPLESCRIPT'
set activities to {"Stretched / Mobility", "Squats / Leg work", "Walked around", "Got water", "Eye break (looked outside)", "Shoulder / Neck rolls", "Just stood up briefly"}
set theChoice to choose from list activities with title "🦵 Welcome back!" with prompt "What did you do during your break?" default items {"Just stood up briefly"}
if theChoice is false then
    return "skipped"
else
    return item 1 of theChoice
end if
APPLESCRIPT
        ) || true
    fi
    echo "$result"
}

# === Interactive dialog ===

ask_still_sitting() {
    local sitting_min=${1:-0}
    local result

    if [[ "$LANGUAGE" == "de" ]]; then
        local btn_away="War weg 🚶"
        local btn_here="War hier 📖"
        local title="🦵 Bewegungscheck"
        if [[ "$sitting_min" -ge "$SIT_LIMIT_MIN" ]]; then
            local reason_text=""
            [[ -n "$REASON" ]] && reason_text=" ($REASON)"
            local dialog_line1="Du sitzt seit ${sitting_min} Min.${reason_text} — Zeit fuer Bewegung!"
            local dialog_line2="Du hast 5 Min. nichts getippt. Was hast du gemacht?"
        else
            local dialog_line1="Du hast 5 Min. nichts getippt."
            local dialog_line2="Was hast du gemacht?"
        fi
    else
        local btn_away="Was away 🚶"
        local btn_here="Was here 📖"
        local title="🦵 Movement check"
        if [[ "$sitting_min" -ge "$SIT_LIMIT_MIN" ]]; then
            local reason_text=""
            [[ -n "$REASON" ]] && reason_text=" ($REASON)"
            local dialog_line1="You've been sitting for ${sitting_min} min${reason_text} — time to move!"
            local dialog_line2="No keyboard/mouse for 5 min. What were you doing?"
        else
            local dialog_line1="No keyboard/mouse activity for 5 min."
            local dialog_line2="What were you doing?"
        fi
    fi

    result=$(osascript \
        -e "set theResult to display dialog \"${dialog_line1}\" & return & \"${dialog_line2}\" buttons {\"${btn_away}\", \"${btn_here}\"} default button \"${btn_here}\" with title \"${title}\" with icon caution giving up after 300" \
        -e 'if gave up of theResult then' \
        -e '    return "gave_up"' \
        -e 'else' \
        -e '    return button returned of theResult' \
        -e 'end if' \
    ) || true
    echo "$result"
}

# === Notification ===

send_notification() {
    local sitting_min=${1:-35}
    local motivation
    local activity
    motivation=$(get_motivational_message)
    activity=$(get_random_activity)

    local reason_suffix=""
    [[ -n "$REASON" ]] && reason_suffix=" ($REASON)"

    if [[ "$LANGUAGE" == "de" ]]; then
        local title="🦵 Zeit fuer Bewegung!${reason_suffix}"
        local subtitle="${sitting_min} Min. am Stueck gesessen"
        local msg="${motivation} → ${activity}"
    else
        local title="🦵 Time to move!${reason_suffix}"
        local subtitle="${sitting_min} min sitting"
        local msg="${motivation} → ${activity}"
    fi

    osascript -e "display notification \"$msg\" with title \"$title\" subtitle \"$subtitle\" sound name \"Funk\""

    log_msg "NOTIFY: ${motivation} | ${activity} (${sitting_min} min)"
}

# ============================================================
# Main logic — runs every 2 min via launchd
# ============================================================

main() {
    # 1. Active hours check
    if ! is_within_active_hours; then
        log_msg "SKIP: Outside active hours"
        exit 0
    fi

    # 2. Screen lock / display off → break
    if is_screen_locked || is_display_off; then
        read_state
        do_break "Screen locked or display off"
        exit 0
    fi

    # 3. Read idle time + state
    local idle_sec now sitting_duration sitting_min
    idle_sec=$(get_idle_seconds)
    read_state
    now=$(date +%s)
    sitting_duration=$(( now - last_break_epoch ))
    sitting_min=$(( sitting_duration / 60 ))

    # 4. Break confirmation: user returned from break → ask what they did
    if [[ "${break_pending:-0}" -eq 1 && "$idle_sec" -lt "$IDLE_ASK_SEC" ]]; then
        log_msg "WELCOME: User returned from break, asking activity"
        local activity_done
        activity_done=$(ask_break_activity)
        if [[ "$activity_done" != "skipped" && -n "$activity_done" ]]; then
            log_msg "ACTIVITY: $activity_done"
        fi
        break_pending=0
        write_state
    fi

    # 5. Auto-break: 10+ min idle, no dialog answered
    if [[ "$idle_sec" -ge "$IDLE_AUTOBREAK_SEC" && "${idle_asked_epoch:-0}" -eq 0 ]]; then
        do_break "Auto-break after ${idle_sec}s idle (no dialog answered)"
        exit 0
    fi

    # 6. Dialog: 5+ min idle, cooldown expired
    local dialog_shown=0
    if [[ "$idle_sec" -ge "$IDLE_ASK_SEC" ]]; then
        local should_ask=0
        if [[ "${idle_asked_epoch:-0}" -eq 0 ]]; then
            should_ask=1
        elif [[ $(( now - idle_asked_epoch )) -ge "$DIALOG_COOLDOWN_SEC" ]]; then
            should_ask=1
        fi

        if [[ "$should_ask" -eq 1 ]]; then
            log_msg "ASK: Idle ${idle_sec}s, sitting ${sitting_min} min"
            local answer
            answer=$(ask_still_sitting "$sitting_min")

            if [[ "$answer" == *"weg"* || "$answer" == *"away"* ]]; then
                do_break "User was away"
                exit 0
            elif [[ "$answer" == *"hier"* || "$answer" == *"here"* ]]; then
                idle_asked_epoch=$now
                if [[ "$sitting_min" -ge "$SIT_LIMIT_MIN" ]]; then
                    notified_epoch=$now
                fi
                write_state
                log_msg "SITTING: User was here, timer continues"
                dialog_shown=1
            else
                do_break "Dialog timeout — user likely away"
                exit 0
            fi
        fi
    fi

    # 7. Time jump check (sleep/restart)
    if [[ "$sitting_duration" -gt 14400 && "$idle_sec" -ge "$IDLE_ASK_SEC" ]]; then
        do_break "Time jump detected (${sitting_duration}s sitting + ${idle_sec}s idle)"
        exit 0
    fi

    log_msg "CHECK: Sitting ${sitting_min} min, idle ${idle_sec}s, notified=${notified_epoch:-0}, asked=${idle_asked_epoch:-0}"

    # 8. Stand-up reminder (notification)
    if [[ "$dialog_shown" -eq 0 && "$sitting_duration" -ge "$SIT_LIMIT_SEC" ]]; then
        local should_notify=0
        if [[ "${notified_epoch:-0}" -eq 0 ]]; then
            should_notify=1
        elif [[ $(( now - notified_epoch )) -ge "$RENOTIFY_SEC" ]]; then
            should_notify=1
        fi

        if [[ "$should_notify" -eq 1 ]]; then
            send_notification "$sitting_min"
            notified_epoch=$now
            write_state
        fi
    fi
}

main "$@"
