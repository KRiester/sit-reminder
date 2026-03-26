INSTALL_DIR  := $(HOME)/.local/bin
CONFIG_DIR   := $(HOME)/.config/sit-reminder
STATE_DIR    := $(HOME)/.local/share/sit-reminder
PLIST_DIR    := $(HOME)/Library/LaunchAgents
PLIST_NAME   := com.sit-reminder.plist
SCRIPT_NAME  := sit-reminder.sh

.PHONY: install uninstall status stats test logs help

help: ## Show available commands
	@echo ""
	@echo "  🦵 Sit-Reminder"
	@echo "  ───────────────"
	@echo "  make install    Install and start sit-reminder"
	@echo "  make uninstall  Stop and remove everything"
	@echo "  make status     Check if sit-reminder is running"
	@echo "  make stats      Show today's break statistics"
	@echo "  make test       Send a test notification now"
	@echo "  make logs       Show recent log entries"
	@echo "  make help       Show this help"
	@echo ""

install: ## Interactive install
	@echo ""
	@echo "  🦵 Sit-Reminder Setup"
	@echo "  ─────────────────────"
	@echo ""
	@# Collect settings interactively
	@SIT_LIMIT_MIN="" && \
	RENOTIFY_MIN="" && \
	HOUR_START="" && \
	HOUR_END="" && \
	LANG_CHOICE="" && \
	REASON="" && \
	printf "  Sit limit in minutes [35]: " && read SIT_LIMIT_MIN && \
	printf "  Remind again every X minutes [20]: " && read RENOTIFY_MIN && \
	printf "  Active hours start (0-23) [7]: " && read HOUR_START && \
	printf "  Active hours end (0-23) [22]: " && read HOUR_END && \
	printf "  Language (en/de) [en]: " && read LANG_CHOICE && \
	printf "  Personal reason, e.g. \"knee health\" (optional) []: " && read REASON && \
	echo "" && \
	SIT_LIMIT_MIN=$${SIT_LIMIT_MIN:-35} && \
	RENOTIFY_MIN=$${RENOTIFY_MIN:-20} && \
	HOUR_START=$${HOUR_START:-7} && \
	HOUR_END=$${HOUR_END:-22} && \
	LANG_CHOICE=$${LANG_CHOICE:-en} && \
	\
	mkdir -p "$(INSTALL_DIR)" && \
	mkdir -p "$(CONFIG_DIR)" && \
	mkdir -p "$(STATE_DIR)" && \
	\
	cp $(SCRIPT_NAME) "$(INSTALL_DIR)/$(SCRIPT_NAME)" && \
	chmod +x "$(INSTALL_DIR)/$(SCRIPT_NAME)" && \
	\
	if [ ! -f "$(CONFIG_DIR)/config" ]; then \
		sed \
			-e "s/^SIT_LIMIT_MIN=.*/SIT_LIMIT_MIN=$$SIT_LIMIT_MIN/" \
			-e "s/^RENOTIFY_MIN=.*/RENOTIFY_MIN=$$RENOTIFY_MIN/" \
			-e "s/^ACTIVE_HOUR_START=.*/ACTIVE_HOUR_START=$$HOUR_START/" \
			-e "s/^ACTIVE_HOUR_END=.*/ACTIVE_HOUR_END=$$HOUR_END/" \
			-e "s/^LANGUAGE=.*/LANGUAGE=$$LANG_CHOICE/" \
			-e "s/^REASON=.*/REASON=\"$$REASON\"/" \
			config.example > "$(CONFIG_DIR)/config"; \
		echo "  Created config: $(CONFIG_DIR)/config"; \
	else \
		echo "  Config already exists: $(CONFIG_DIR)/config (kept)"; \
	fi && \
	\
	printf '%s\n' \
		'<?xml version="1.0" encoding="UTF-8"?>' \
		'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
		'<plist version="1.0">' \
		'<dict>' \
		'    <key>Label</key>' \
		'    <string>com.sit-reminder</string>' \
		'    <key>ProgramArguments</key>' \
		'    <array>' \
		'        <string>/bin/bash</string>' \
		"        <string>$(INSTALL_DIR)/$(SCRIPT_NAME)</string>" \
		'    </array>' \
		'    <key>StartInterval</key>' \
		'    <integer>120</integer>' \
		'    <key>ProcessType</key>' \
		'    <string>Background</string>' \
		'    <key>StandardOutPath</key>' \
		"    <string>$(STATE_DIR)/launchd-stdout.log</string>" \
		'    <key>StandardErrorPath</key>' \
		"    <string>$(STATE_DIR)/launchd-stderr.log</string>" \
		'    <key>RunAtLoad</key>' \
		'    <true/>' \
		'</dict>' \
		'</plist>' > "$(PLIST_DIR)/$(PLIST_NAME)" && \
	\
	launchctl unload "$(PLIST_DIR)/$(PLIST_NAME)" 2>/dev/null || true && \
	launchctl load "$(PLIST_DIR)/$(PLIST_NAME)" && \
	\
	echo "" && \
	echo "  ✅ Installed and running!" && \
	echo "" && \
	echo "  Config:  $(CONFIG_DIR)/config" && \
	echo "  Script:  $(INSTALL_DIR)/$(SCRIPT_NAME)" && \
	echo "  Logs:    $(STATE_DIR)/sit-reminder.log" && \
	echo "" && \
	echo "  Tip: Edit the config anytime — changes take effect within 2 minutes." && \
	echo "  Run 'make test' to see a test notification now." && \
	echo ""

uninstall: ## Remove sit-reminder completely
	@echo ""
	@launchctl unload "$(PLIST_DIR)/$(PLIST_NAME)" 2>/dev/null || true
	@rm -f "$(PLIST_DIR)/$(PLIST_NAME)"
	@rm -f "$(INSTALL_DIR)/$(SCRIPT_NAME)"
	@rm -rf "$(STATE_DIR)"
	@echo "  ✅ Uninstalled."
	@echo "  Config kept at: $(CONFIG_DIR)/config"
	@echo "  To remove config too: rm -rf $(CONFIG_DIR)"
	@echo ""

status: ## Check if sit-reminder is running
	@echo ""
	@if launchctl list 2>/dev/null | grep -q "com.sit-reminder"; then \
		echo "  ✅ Sit-Reminder is running."; \
		echo ""; \
		if [ -f "$(STATE_DIR)/state" ]; then \
			. "$(STATE_DIR)/state" 2>/dev/null; \
			NOW=$$(date +%s); \
			SITTING=$$(( (NOW - last_break_epoch) / 60 )); \
			echo "  Current session: $${SITTING} min sitting"; \
		fi; \
	else \
		echo "  ❌ Sit-Reminder is not running."; \
		echo "  Run 'make install' to start it."; \
	fi
	@echo ""
	@if [ -f "$(STATE_DIR)/sit-reminder.log" ]; then \
		echo "  Last 5 log entries:"; \
		tail -5 "$(STATE_DIR)/sit-reminder.log" | sed 's/^/  /'; \
	fi
	@echo ""

stats: ## Show today's break statistics
	@echo ""
	@echo "  📊 Today's Stats ($$(date '+%Y-%m-%d'))"
	@echo "  ─────────────────────────"
	@if [ -f "$(STATE_DIR)/sit-reminder.log" ]; then \
		TODAY=$$(date '+%Y-%m-%d'); \
		BREAKS=$$(grep "^$$TODAY" "$(STATE_DIR)/sit-reminder.log" | grep -c "BREAK:" || echo 0); \
		NOTIFS=$$(grep "^$$TODAY" "$(STATE_DIR)/sit-reminder.log" | grep -c "NOTIFY:" || echo 0); \
		CHECKS=$$(grep "^$$TODAY" "$(STATE_DIR)/sit-reminder.log" | grep -c "CHECK:" || echo 0); \
		TOTAL_MIN=$$(( CHECKS * 2 )); \
		HOURS=$$(( TOTAL_MIN / 60 )); \
		MINS=$$(( TOTAL_MIN % 60 )); \
		echo "  Breaks taken:      $$BREAKS"; \
		echo "  Reminders sent:    $$NOTIFS"; \
		echo "  Time at computer:  ~$${HOURS}h $${MINS}m"; \
		echo ""; \
		if [ "$$BREAKS" -gt 0 ]; then \
			echo "  💪 Keep it up!"; \
		elif [ "$$NOTIFS" -gt 0 ]; then \
			echo "  🦵 You got reminders but no breaks yet — time to move!"; \
		else \
			echo "  Just getting started today."; \
		fi; \
	else \
		echo "  No data yet. Sit-Reminder will start logging once installed."; \
	fi
	@echo ""

test: ## Send a test notification right now
	@echo ""
	@bash "$(INSTALL_DIR)/$(SCRIPT_NAME)" 2>/dev/null || bash $(SCRIPT_NAME) 2>/dev/null || echo "  Run 'make install' first."
	@echo "  ✅ Test run complete. Check your notifications!"
	@echo ""

logs: ## Show recent log entries
	@echo ""
	@if [ -f "$(STATE_DIR)/sit-reminder.log" ]; then \
		echo "  Last 20 log entries:"; \
		echo "  ────────────────────"; \
		tail -20 "$(STATE_DIR)/sit-reminder.log" | sed 's/^/  /'; \
	else \
		echo "  No log file found. Run 'make install' first."; \
	fi
	@echo ""
