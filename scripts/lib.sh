#!/usr/bin/env bash
# Shared helpers for the ecosystem scripts. Sourced by start.sh, stop.sh,
# setup.sh, doctor.sh and status.sh — never executed directly.
#
# The last time this repo needed a second entry point (the deleted start-all.sh)
# it copy-pasted these helpers instead of sharing them, and the duplication is
# what eventually got deleted. Everything common lives here.

# Resolve paths relative to this file so callers do not each recompute them.
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$LIB_DIR")"
LOG_DIR="$REPO_DIR/logs"
ENV_FILE="$REPO_DIR/.env"
SECRETS_FILE="$REPO_DIR/.env.secrets"

# Colours
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
DIM='\033[2m'
NC='\033[0m'

# ── Small predicates ─────────────────────────────────────────────────────────

have() { command -v "$1" >/dev/null 2>&1; }

# macOS ships a /usr/bin/java shim that exists on PATH and fails when no JDK is
# installed, so `have java` is a false positive there. Actually run it.
have_java() { java -version >/dev/null 2>&1; }

port_open() { nc -z localhost "$1" 2>/dev/null; }

# True when logs/<name>.pid names a live process.
pid_alive() {
    local pid_file="$LOG_DIR/$1.pid"
    [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null
}

check_repo() {
    local name="$1"
    if [ ! -d "$REPO_DIR/$name" ]; then
        echo -e "${RED}Error:${NC} $REPO_DIR/$name not found. Run 'make setup' first."
        exit 1
    fi
}

# ── Configuration ────────────────────────────────────────────────────────────

# Load the root .env and .env.secrets into this shell. Both are optional: with
# neither present every service falls back to its own .env and its own defaults,
# which is exactly how the ecosystem behaved before the root config existed.
load_env() {
    set -a
    # shellcheck disable=SC1090
    [ -f "$ENV_FILE" ] && . "$ENV_FILE"
    # shellcheck disable=SC1090
    [ -f "$SECRETS_FILE" ] && . "$SECRETS_FILE"
    set +a

    # Defaults for anything the files did not set, so every caller can rely on
    # these being populated. These mirror .env.example.
    : "${MARKET_DATA_PORT:=8082}"
    : "${INVESTPAL_API_PORT:=8000}"
    : "${INVESTPAL_MCP_PORT:=9000}"
    : "${COINBASE_MCP_PORT:=9090}"
    : "${ALPACA_MCP_PORT:=9091}"
    : "${IB_MCP_PORT:=9092}"
    : "${IB_GATEWAY_PORT:=5000}"

    : "${LLM_PROVIDER:=anthropic}"
    : "${LLM_MODEL:=claude-sonnet-4-6}"
    : "${TURSO_DB_PATH:=investpal.db}"
    : "${EMBEDDING_ENABLED:=true}"
    : "${EMBEDDING_CACHE_DIR:=$HOME/.cache/investpal/fastembed}"
    : "${CONNECT_BROKERS_TO_BACKEND:=false}"

    : "${ALPACA_READ_ONLY:=false}"
    : "${COINBASE_READ_ONLY:=false}"
    : "${IB_READ_ONLY:=false}"
    : "${IB_PORTAL_BASE_URL:=https://localhost:${IB_GATEWAY_PORT}/v1/api}"
}

# True when the root config exists at all. Without it service_env stays silent
# and the per-service .env files remain authoritative.
root_config_present() { [ -f "$ENV_FILE" ] || [ -f "$SECRETS_FILE" ]; }

# Echo KEY=VALUE pairs, one per line, for a given service. This is the single
# place ports, cross-service URLs and credential name mappings are defined.
#
# Three collisions are resolved here and nowhere else: MCP_PORT and READ_ONLY
# are each used by three different services, and Coinbase's settings fields are
# coinbase_key_name / coinbase_key_secret rather than the COINBASE_API_KEY /
# COINBASE_API_SECRET spelling .mcp.json uses. pydantic-settings is
# case-insensitive, so the uppercase exports bind correctly.
#
# Exporting extra variables is safe: pydantic's EnvSettingsSource only looks up
# declared field names, and extra="forbid" applies to keys inside a dotenv file,
# not to the process environment. Go's godotenv.Load() never overwrites an
# existing variable either. So exported values win, and no .env file is ever
# written into a sibling repo.
service_env() {
    root_config_present || return 0

    case "$1" in
        market-data-mcp)
            emit PORT "$MARKET_DATA_PORT"
            emit SEC_EDGAR_USER_AGENT "$SEC_EDGAR_USER_AGENT"
            emit COIN_GECKO_API_KEY "$COIN_GECKO_API_KEY"
            emit CACHE_TTL "$CACHE_TTL"
            ;;
        alpaca-mcp)
            emit MCP_PORT "$ALPACA_MCP_PORT"
            emit READ_ONLY "$ALPACA_READ_ONLY"
            emit ALPACA_API_KEY "$ALPACA_API_KEY"
            emit ALPACA_API_SECRET "$ALPACA_API_SECRET"
            emit ALPACA_API_BASE_URL "$ALPACA_API_BASE_URL"
            ;;
        coinbase-mcp)
            emit MCP_PORT "$COINBASE_MCP_PORT"
            emit READ_ONLY "$COINBASE_READ_ONLY"
            emit COINBASE_KEY_NAME "$COINBASE_API_KEY"
            emit COINBASE_KEY_SECRET "$COINBASE_API_SECRET"
            ;;
        interactive-brokers-mcp)
            emit MCP_PORT "$IB_MCP_PORT"
            emit READ_ONLY "$IB_READ_ONLY"
            emit INTERACTIVE_BROKERS_PORTAL_BASE_URL "$IB_PORTAL_BASE_URL"
            ;;
        investpal-api|investpal-mcp)
            # LLM_PROVIDER, LLM_MODEL and MARKET_DATA_MCP_SERVER_URL have no
            # defaults in InvestPal/config.py, so pydantic kills both processes
            # at import without them. All three are derivable, so they are
            # always supplied and never asked for during setup.
            emit LLM_PROVIDER "$LLM_PROVIDER"
            emit LLM_MODEL "$LLM_MODEL"
            emit MARKET_DATA_MCP_SERVER_URL "http://localhost:$MARKET_DATA_PORT"
            emit MCP_APP_SERVER_PORT "$INVESTPAL_MCP_PORT"
            emit TURSO_DB_PATH "$TURSO_DB_PATH"
            emit EMBEDDING_ENABLED "$EMBEDDING_ENABLED"

            emit ANTHROPIC_API_KEY "$ANTHROPIC_API_KEY"
            emit OPENAI_API_KEY "$OPENAI_API_KEY"
            emit GOOGLE_API_KEY "$GOOGLE_API_KEY"

            emit TURSO_SYNC_URL "$TURSO_SYNC_URL"
            emit TURSO_SYNC_AUTH_TOKEN "$TURSO_SYNC_AUTH_TOKEN"
            emit TURSO_SYNC_CLIENT_NAME "$TURSO_SYNC_CLIENT_NAME"

            # The backend agent gets broker tools only when asked. Left off, the
            # cockpit still reaches both brokers directly over .mcp.json.
            if [ "$CONNECT_BROKERS_TO_BACKEND" = "true" ]; then
                emit ALPACA_MCP_SERVER_URL "http://localhost:$ALPACA_MCP_PORT"
                emit COINBASE_MCP_SERVER_URL "http://localhost:$COINBASE_MCP_PORT"
            fi

            # Once the ~67MB model is cached, going offline skips a HuggingFace
            # metadata round-trip on every load. Only safe after a first fetch.
            if [ -d "$EMBEDDING_CACHE_DIR" ] && [ -n "$(ls -A "$EMBEDDING_CACHE_DIR" 2>/dev/null)" ]; then
                emit HF_HUB_OFFLINE 1
            fi
            ;;
    esac
}

# Helper for service_env: skip empty values so a blank key never shadows a
# service's own default with an empty string.
emit() { [ -n "$2" ] && printf '%s=%s\n' "$1" "$2"; return 0; }

# ── Process lifecycle ────────────────────────────────────────────────────────

# start_service <name> <dir> <cmd> [KEY=VALUE ...]
# Env pairs are passed as separate arguments so values containing spaces survive.
start_service() {
    local name="$1"
    local dir="$2"
    local cmd="$3"
    shift 3
    local pid_file="$LOG_DIR/$name.pid"
    local log_file="$LOG_DIR/$name.log"

    if pid_alive "$name"; then
        echo -e "  ${YELLOW}$name${NC} already running (PID $(cat "$pid_file"))"
        return
    fi

    echo -e "  Starting ${GREEN}$name${NC}..."
    if [ "$#" -gt 0 ]; then
        (cd "$dir" && export "$@" && eval "$cmd" >> "$log_file" 2>&1) &
    else
        (cd "$dir" && eval "$cmd" >> "$log_file" 2>&1) &
    fi
    local pid=$!
    disown "$pid"
    echo "$pid" > "$pid_file"
}

# Fourth argument is "required" (default) or "optional". An optional service that
# never comes up returns 1 for the caller to handle instead of aborting startup.
wait_for_port() {
    local name="$1"
    local port="$2"
    local retries="${3:-30}"
    local mode="${4:-required}"

    echo -n "  Waiting for $name to be ready on port $port"
    for _ in $(seq 1 "$retries"); do
        if port_open "$port"; then
            echo -e " ${GREEN}OK${NC}"
            return 0
        fi
        echo -n "."
        sleep 1
    done
    echo -e " ${RED}TIMEOUT${NC}"
    if [ "$mode" = "optional" ]; then
        echo -e "  ${YELLOW}Warning:${NC} $name did not start in time. Check logs/, continuing."
        return 1
    fi
    echo -e "${RED}Error:${NC} $name did not start in time. Check logs/$name.log"
    exit 1
}

# Kill a process and all its descendants recursively.
kill_tree() {
    local pid="$1"
    local children
    children=$(pgrep -P "$pid" 2>/dev/null) || true
    for child in $children; do
        kill_tree "$child"
    done
    kill "$pid" 2>/dev/null || true
}

# ── Reporting ────────────────────────────────────────────────────────────────

# The running-services table, shared by start.sh and status.sh so the two can
# never drift. Reads ports from the loaded config.
service_table() {
    echo "  Service                      Port   Log"
    echo "  ─────────────────────────────────────────────────────────────"
    printf "  %-28s %-6s %s\n" "InvestPal REST API"   "$INVESTPAL_API_PORT" "logs/investpal-api.log"
    printf "  %-28s %-6s %s\n" "InvestPal MCP App"    "$INVESTPAL_MCP_PORT" "logs/investpal-mcp.log"
    printf "  %-28s %-6s %s\n" "MarketDataMcpServer"  "$MARKET_DATA_PORT"   "logs/market-data-mcp.log"
    printf "  %-28s %-6s %s\n" "AlpacaMcpServer"      "$ALPACA_MCP_PORT"    "logs/alpaca-mcp.log"
    printf "  %-28s %-6s %s\n" "CoinbaseMcpServer"    "$COINBASE_MCP_PORT"  "logs/coinbase-mcp.log"
    if pid_alive "interactive-brokers-mcp"; then
        printf "  %-28s %-6s %s\n" "InteractiveBrokersMcpServer" "$IB_MCP_PORT" "logs/interactive-brokers-mcp.log"
    fi
    if pid_alive "ib-gateway"; then
        printf "  %-28s %-6s %s\n" "IB Client Portal Gateway" "$IB_GATEWAY_PORT" "logs/ib-gateway.log"
    fi
}
