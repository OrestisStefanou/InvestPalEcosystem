#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$REPO_DIR/logs"

# Colours
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_repo() {
    local name="$1"
    if [ ! -d "$REPO_DIR/$name" ]; then
        echo -e "${RED}Error:${NC} $REPO_DIR/$name not found. Run 'make clone' first."
        exit 1
    fi
}

start_service() {
    local name="$1"
    local dir="$2"
    local cmd="$3"
    local pid_file="$LOG_DIR/$name.pid"
    local log_file="$LOG_DIR/$name.log"

    if [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
        echo -e "  ${YELLOW}$name${NC} already running (PID $(cat "$pid_file"))"
        return
    fi

    echo -e "  Starting ${GREEN}$name${NC}..."
    (cd "$dir" && eval "$cmd" >> "$log_file" 2>&1) &
    local pid=$!
    disown "$pid"
    echo "$pid" > "$pid_file"
}

# ── 1. Start backend infrastructure ─────────────────────────────────────────
bash "$SCRIPT_DIR/start.sh"

# ── 2. Start Telegram bot ────────────────────────────────────────────────────
echo ""
echo "Starting Telegram bot..."
check_repo "InvestPalTelegramBot"

start_service "telegram-bot" "$REPO_DIR/InvestPalTelegramBot" "uv run python main.py"

echo ""
echo -e "${GREEN}Telegram bot started.${NC}"
echo ""
echo "  Service       Log"
echo "  ──────────────────────────────────────"
echo "  telegram-bot  logs/telegram-bot.log"
echo ""
echo "Run 'make logs' to tail all logs, or 'make stop' to stop all services."
