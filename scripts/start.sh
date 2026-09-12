#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

mkdir -p "$LOG_DIR"
load_env

# ── Check all repos exist ────────────────────────────────────────────────────
echo "Checking repositories..."
check_repo "AlpacaMcpServer"
check_repo "CoinbaseMcpServer"
check_repo "InvestPal"

echo ""
echo "Starting services..."

# Set by any optional service that fails to come up, so the closing summary can
# say "some services" instead of claiming everything started.
OPTIONAL_FAILED=false

# ── 1. Market data: two OpenBB instances ─────────────────────────────────────
# One server setting decides this and it is server-wide, which is why there are
# two processes rather than one:
#
#   8082  static, --default-categories, ~153 tools always enabled.
#         InvestPal's two LangChain agents bind their tool list at construction
#         time and open a fresh MCP session per call, so discovery mode would
#         leave them looking at six admin tools forever.
#   8083  --tool-discovery, ~6 admin tools, all 287 reachable per session.
#         Claude Code and Claude Desktop hold a persistent session, so
#         activate_tools' per-session enabling actually works for them. This is
#         the one .mcp.json points at.
#
# Both load the full OpenBB platform, so first start is slow and the timeouts
# below are generous. The static instance is required — InvestPal dies in
# pydantic at import without MARKET_DATA_MCP_SERVER_URL answering — while the
# discovery instance is optional, so a cockpit-only failure does not abort
# `make start` for the backend.
if [ ! -x "$(openbb_bin)" ]; then
    echo -e "${RED}Error:${NC} $(openbb_bin) not found. Run 'make install' first."
    exit 1
fi

collect_env market-data-mcp
start_service "market-data-mcp" "$MARKET_DATA_PORT" "$REPO_DIR" \
    "$(openbb_cmd "$MARKET_DATA_PORT" --default-categories "$MARKET_DATA_CATEGORIES")" \
    "${ENV_PAIRS[@]}"
wait_for_service "Market Data (OpenBB)" "market-data-mcp" "$MARKET_DATA_PORT" 90

collect_env market-data-discovery-mcp
start_service "market-data-discovery-mcp" "$MARKET_DATA_DISCOVERY_PORT" "$REPO_DIR" \
    "$(openbb_cmd "$MARKET_DATA_DISCOVERY_PORT" --tool-discovery)" \
    "${ENV_PAIRS[@]}"
wait_for_service "Market Data Discovery" "market-data-discovery-mcp" "$MARKET_DATA_DISCOVERY_PORT" 90 optional \
    || OPTIONAL_FAILED=true

# ── 1b. Legacy Go market-data server ─────────────────────────────────────────
# TEMPORARY — Phase A of the OpenBB cutover, and nothing else. It runs on its
# own port with nothing pointed at it, so that answers from the two servers can
# be compared side by side during the changeover and a rollback is one env var
# (MARKET_DATA_MCP_SERVER_URL) rather than a redeploy.
#
# Off unless MARKET_DATA_LEGACY_ENABLED=true in .env, and always optional. At
# Phase C, delete this block, the market-data-legacy case in lib.sh, the legacy
# rows and defaults there, and the Go build in the Makefile.
if [ "$MARKET_DATA_LEGACY_ENABLED" = "true" ]; then
    if [ ! -d "$REPO_DIR/MarketDataMcpServer" ]; then
        echo -e "  ${YELLOW}Skipping legacy market-data server:${NC} MarketDataMcpServer/ is not cloned."
    else
        collect_env market-data-legacy
        start_service "market-data-legacy" "$MARKET_DATA_LEGACY_PORT" \
            "$REPO_DIR/MarketDataMcpServer" "make run_mcp_server" "${ENV_PAIRS[@]}"
        wait_for_service "Market Data (legacy Go)" "market-data-legacy" "$MARKET_DATA_LEGACY_PORT" 30 optional \
            || OPTIONAL_FAILED=true
    fi
fi

# ── 2. AlpacaMcpServer ───────────────────────────────────────────────────────
# Optional, like Coinbase below. Without credentials the server still starts and
# stays healthy, it just registers no tools, and the persona is written to work
# without broker tools. Gated all the same, so a server that fails to come up is
# reported here instead of showing up as a dead MCP server.
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
