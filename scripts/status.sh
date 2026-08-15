#!/usr/bin/env bash
# What is running right now. The runtime slice of `make doctor`, in the same
# table `make start` prints.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

load_env

row() { # row LABEL PID_NAME PORT
    local label="$1" name="$2" port="$3" state
    if pid_alive "$name" && port_open "$port"; then
        state="${GREEN}running${NC}"
    elif pid_alive "$name"; then
        state="${YELLOW}starting${NC}"
    elif port_open "$port"; then
        state="${YELLOW}foreign${NC}"
    else
        state="${RED}stopped${NC}"
    fi
    printf "  %-28s %-6s %b\n" "$label" "$port" "$state"
}

echo ""
printf "  %-28s %-6s %s\n" "Service" "Port" "State"
echo "  ─────────────────────────────────────────────────"
row "InvestPal REST API"   investpal-api  "$INVESTPAL_API_PORT"
row "InvestPal MCP App"    investpal-mcp  "$INVESTPAL_MCP_PORT"
row "MarketDataMcpServer"  market-data-mcp "$MARKET_DATA_PORT"
row "AlpacaMcpServer"      alpaca-mcp     "$ALPACA_MCP_PORT"
row "CoinbaseMcpServer"    coinbase-mcp   "$COINBASE_MCP_PORT"
if [ -d "$REPO_DIR/InteractiveBrokersMcpServer" ]; then
    row "InteractiveBrokersMcpServer" interactive-brokers-mcp "$IB_MCP_PORT"
    row "IB Client Portal Gateway"    ib-gateway              "$IB_GATEWAY_PORT"
fi
echo ""
echo "  'make doctor' for a full diagnosis, 'make logs' to tail output."
