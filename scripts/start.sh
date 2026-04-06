#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$REPO_DIR/logs"

mkdir -p "$LOG_DIR"

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
    echo $! > "$pid_file"
}

wait_for_port() {
    local name="$1"
    local port="$2"
    local retries=30

    echo -n "  Waiting for $name to be ready on port $port"
    for i in $(seq 1 $retries); do
        if nc -z localhost "$port" 2>/dev/null; then
            echo -e " ${GREEN}OK${NC}"
            return 0
        fi
        echo -n "."
        sleep 1
    done
    echo -e " ${RED}TIMEOUT${NC}"
    echo -e "${RED}Error:${NC} $name did not start in time. Check logs/$name.log"
    exit 1
}

# ── Check all repos exist ────────────────────────────────────────────────────
echo "Checking repositories..."
check_repo "MarketDataMcpServer"
check_repo "AlpacaMcpServer"
check_repo "CoinbaseMcpServer"
check_repo "InvestPal"

echo ""
echo "Starting services..."

# ── 1. MarketDataMcpServer (required by InvestPal) ───────────────────────────
start_service "market-data-mcp" "$REPO_DIR/MarketDataMcpServer" "make run_mcp_server"
wait_for_port "MarketDataMcpServer" 8080

# ── 2. AlpacaMcpServer ───────────────────────────────────────────────────────
start_service "alpaca-mcp" "$REPO_DIR/AlpacaMcpServer" "uv run python main.py"

# ── 3. CoinbaseMcpServer ─────────────────────────────────────────────────────
start_service "coinbase-mcp" "$REPO_DIR/CoinbaseMcpServer" "uv run main.py"

# ── 4. InvestPal REST API ────────────────────────────────────────────────────
start_service "investpal-api" "$REPO_DIR/InvestPal" "uv run fastapi run main.py"

# ── 5. InvestPal MCP App ─────────────────────────────────────────────────────
start_service "investpal-mcp" "$REPO_DIR/InvestPal" "uv run python3 -m apps.mcp_api.app"

echo ""
echo -e "${GREEN}All services started.${NC}"
echo ""
echo "  Service              Port   Log"
echo "  ─────────────────────────────────────────────────────"
echo "  InvestPal REST API   8000   logs/investpal-api.log"
echo "  InvestPal MCP App    9000   logs/investpal-mcp.log"
echo "  MarketDataMcpServer  8080   logs/market-data-mcp.log"
echo "  AlpacaMcpServer      9091   logs/alpaca-mcp.log"
echo "  CoinbaseMcpServer    9090   logs/coinbase-mcp.log"
echo ""
echo "Run 'make logs' to tail all logs, or 'make stop' to stop all services."
