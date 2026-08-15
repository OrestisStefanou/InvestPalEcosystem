#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

mkdir -p "$LOG_DIR"
load_env

# Collect a service's fan-out pairs into an array. Written as a read loop rather
# than mapfile so this keeps working on the bash 3.2 that ships with macOS.
collect_env() {
    ENV_PAIRS=()
    local line
    while IFS= read -r line; do
        [ -n "$line" ] && ENV_PAIRS+=("$line")
    done < <(service_env "$1")
}

# ── Check all repos exist ────────────────────────────────────────────────────
echo "Checking repositories..."
check_repo "MarketDataMcpServer"
check_repo "AlpacaMcpServer"
check_repo "CoinbaseMcpServer"
check_repo "InvestPal"

echo ""
echo "Starting services..."

# Set by any optional service that fails to come up, so the closing summary can
# say "some services" instead of claiming everything started.
OPTIONAL_FAILED=false

# ── 1. MarketDataMcpServer (required by InvestPal) ───────────────────────────
# With the root config present PORT comes from the fan-out. Without it, fall
# back to reading the service's own .env, as this script always did — noting
# that the Go default is 8080 while the health gate below expects 8082.
if ! root_config_present; then
    MARKET_DATA_PORT=$(grep '^PORT=' "$REPO_DIR/MarketDataMcpServer/.env" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]')
    MARKET_DATA_PORT="${MARKET_DATA_PORT:-8082}"
fi
collect_env market-data-mcp
start_service "market-data-mcp" "$MARKET_DATA_PORT" "$REPO_DIR/MarketDataMcpServer" "make run_mcp_server" "${ENV_PAIRS[@]}"
wait_for_service "MarketDataMcpServer" "market-data-mcp" "$MARKET_DATA_PORT"

# ── 2. AlpacaMcpServer ───────────────────────────────────────────────────────
# Optional, like Coinbase below: without credentials the server exits on startup,
# and the persona is written to work without broker tools. Gated all the same, so
# a missing key is reported here instead of showing up as a dead MCP server.
collect_env alpaca-mcp
start_service "alpaca-mcp" "$ALPACA_MCP_PORT" "$REPO_DIR/AlpacaMcpServer" "uv run python main.py" "${ENV_PAIRS[@]}"
wait_for_service "AlpacaMcpServer" "alpaca-mcp" "$ALPACA_MCP_PORT" 30 optional || OPTIONAL_FAILED=true

# ── 3. CoinbaseMcpServer ─────────────────────────────────────────────────────
collect_env coinbase-mcp
start_service "coinbase-mcp" "$COINBASE_MCP_PORT" "$REPO_DIR/CoinbaseMcpServer" "uv run main.py" "${ENV_PAIRS[@]}"
wait_for_service "CoinbaseMcpServer" "coinbase-mcp" "$COINBASE_MCP_PORT" 30 optional || OPTIONAL_FAILED=true

# ── 4. InteractiveBrokersMcpServer (optional) ────────────────────────────────
# Skipped entirely when the repo is not cloned, so a machine without it still
# gets a working `make start`. Unlike Alpaca and Coinbase there are no API keys:
# the server talks to the IB Client Portal Gateway, a Java process on
# https://localhost:5000 that has to be logged into from a browser.
IB_DIR="$REPO_DIR/InteractiveBrokersMcpServer"
IB_GATEWAY_UP=false

if [ -d "$IB_DIR" ]; then
    IB_GATEWAY_RUN="$IB_DIR/ib_clientportal/bin/run.sh"

    if port_open "$IB_GATEWAY_PORT"; then
        # The gateway keeps its authenticated session across MCP restarts, so a
        # live one is left alone rather than relaunched over.
        echo -e "  ${YELLOW}IB Client Portal Gateway${NC} already listening on port $IB_GATEWAY_PORT"
        IB_GATEWAY_UP=true
    elif [ ! -f "$IB_GATEWAY_RUN" ]; then
        echo -e "  ${YELLOW}Skipping IB Client Portal Gateway:${NC} $IB_GATEWAY_RUN not found."
        echo "    Download the Client Portal API gateway from Interactive Brokers and unpack it"
        echo "    into $IB_DIR/ib_clientportal/. The IB tools stay unusable until it runs."
    elif ! have_java; then
        echo -e "  ${YELLOW}Skipping IB Client Portal Gateway:${NC} java is not on PATH."
        echo "    The gateway needs a Java 1.8+ runtime. The IB tools stay unusable until it runs."
    else
        start_service "ib-gateway" "$IB_GATEWAY_PORT" "$IB_DIR/ib_clientportal" "bin/run.sh root/conf.yaml"
        if wait_for_service "IB Client Portal Gateway" "ib-gateway" "$IB_GATEWAY_PORT" 30 optional; then
            IB_GATEWAY_UP=true
        else
            OPTIONAL_FAILED=true
        fi
    fi

    # A running gateway is not the same as a logged-in one, and an expired session
    # is the usual reason the IB tools start failing. Report it, never fail on it.
    if [ "$IB_GATEWAY_UP" = true ]; then
        # -k because the gateway serves a self-signed certificate.
        IB_AUTH=$(curl -sk --max-time 3 "https://localhost:$IB_GATEWAY_PORT/v1/api/iserver/auth/status" 2>/dev/null) || IB_AUTH=""
        case "$IB_AUTH" in
            *'"authenticated":true'*)
                echo -e "  IB Client Portal Gateway ${GREEN}authenticated${NC}"
                ;;
            *)
                echo -e "  ${YELLOW}IB Client Portal Gateway is not authenticated.${NC}"
                echo "    Open https://localhost:$IB_GATEWAY_PORT and log in with your IB credentials."
                ;;
        esac
    fi

    collect_env interactive-brokers-mcp
    start_service "interactive-brokers-mcp" "$IB_MCP_PORT" "$IB_DIR" "uv run python main.py" "${ENV_PAIRS[@]}"
    wait_for_service "InteractiveBrokersMcpServer" "interactive-brokers-mcp" "$IB_MCP_PORT" 30 optional \
        || OPTIONAL_FAILED=true
fi

# ── 5. InvestPal REST API ────────────────────────────────────────────────────
collect_env investpal-api
start_service "investpal-api" "$INVESTPAL_API_PORT" "$REPO_DIR/InvestPal" "uv run fastapi run main.py" "${ENV_PAIRS[@]}"
# Gated like the MCP app: both open the same turso file at startup, so both fail
# the same way when the database is missing or not initialised for sync.
wait_for_service "InvestPal REST API" "investpal-api" "$INVESTPAL_API_PORT" 60

# ── 6. InvestPal MCP App ─────────────────────────────────────────────────────
# The one service whose failure is felt immediately: Claude Code connects to it
# at launch, so returning before it is listening is what produces the "MCP server
# unreachable" note in the cockpit's SessionStart hook.
if ! root_config_present; then
    INVESTPAL_MCP_PORT=$(grep '^MCP_APP_SERVER_PORT=' "$REPO_DIR/InvestPal/.env" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]')
    INVESTPAL_MCP_PORT="${INVESTPAL_MCP_PORT:-9000}"
fi
collect_env investpal-mcp
start_service "investpal-mcp" "$INVESTPAL_MCP_PORT" "$REPO_DIR/InvestPal" "uv run python3 -m apps.mcp_api.app" "${ENV_PAIRS[@]}"
# Longer timeout than the default: on a cold start this initialises the turso
# schema, and with TURSO_SYNC_URL set it also negotiates with Turso Cloud.
wait_for_service "InvestPal MCP App" "investpal-mcp" "$INVESTPAL_MCP_PORT" 60

echo ""
if [ "$OPTIONAL_FAILED" = true ]; then
    echo -e "${YELLOW}Started, with optional services missing (see above).${NC}"
else
    echo -e "${GREEN}All services started.${NC}"
fi
echo ""
service_table
echo ""
echo "Run 'make logs' to tail all logs, or 'make stop' to stop all services."
