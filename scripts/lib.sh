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

# Node is optional in exactly the sense java is: one component needs it, and
# `make setup` deliberately does not require it. Only `make ui` cares.
have_node() { have node && have npm; }

port_open() { nc -z localhost "$1" 2>/dev/null; }

# The PID of whatever is listening on a TCP port, or empty. `port_open` only
# says the port answers; this says who is answering, which is the difference
# between "our service is up" and "someone else got there first".
port_pid() { lsof -nP -tiTCP:"$1" -sTCP:LISTEN 2>/dev/null | head -1; }

# True when $1 is $2 or one of its descendants. Walks the parent chain upwards
# (O(depth)) rather than scanning the whole process table. Needed because the
# PID we record is a wrapper — bash subshell -> uv/make -> the real server — so
# the listener is never the recorded PID itself.
is_descendant() {
    local pid="$1" ancestor="$2"
    [ -n "$pid" ] && [ -n "$ancestor" ] || return 1
    while [ -n "$pid" ] && [ "$pid" != "0" ] && [ "$pid" != "1" ]; do
        [ "$pid" = "$ancestor" ] && return 0
        pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d '[:space:]')
    done
    return 1
}

# True when logs/<name>.pid names a live process.
pid_alive() {
    local pid_file="$LOG_DIR/$1.pid"
    [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null
}

# The recorded PID for a service, or empty.
service_pid() { cat "$LOG_DIR/$1.pid" 2>/dev/null; }

# True when the service is alive AND owns its port. The conjunction is the point:
# either half on its own reports a service as healthy when it is not.
service_up() {
    pid_alive "$1" && is_descendant "$(port_pid "$2")" "$(service_pid "$1")"
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
    : "${INVESTPAL_WEB_PORT:=5173}"

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

# ── Turso database state ─────────────────────────────────────────────────────
#
# Shared because setup.sh and doctor.sh both have to know which of the four
# situations a machine is in, and both used to work it out for themselves —
# doctor.sh by grepping `turso_status` output for state names it never printed,
# setup.sh by running InvestPal's make without the env fan-out, so pydantic
# killed it before it read the database and every machine looked "ready".

# Absolute path of the local database, wherever TURSO_DB_PATH points.
turso_db_path() {
    local db="${TURSO_DB_PATH:-investpal.db}"
    case "$db" in /*) ;; *) db="$REPO_DIR/InvestPal/$db" ;; esac
    printf '%s' "$db"
}

# fresh | local_only | synced | broken, decided from files exactly as
# InvestPal's db_state() does. The -info sidecar is what makes a file a sync
# database; without it the servers refuse to start.
turso_state() {
    local db
    db="$(turso_db_path)"
    if [ -f "$db" ] && [ -f "$db-info" ]; then echo synced
    elif [ -f "$db" ]; then echo local_only
    elif [ -f "$db-info" ]; then echo broken
    else echo fresh
    fi
}

# Total rows across the tables that hold user data, or non-zero exit when it
# cannot be read (no sqlite3, unreadable file). An empty database and a full one
# look identical from the outside, and telling them apart is what decides
# whether first_pull or first_push is the right advice.
#
# Returns failure unless at least one table actually answered: silently counting
# a string of failed queries as zero would report a populated database as safe
# to discard.
#
# immutable=1, not just -readonly: a plain read of a WAL database builds an
# -shm index next to it, and doctor.sh promises to change nothing. The tradeoff
# is a possibly stale count if a server is writing concurrently, which cannot
# matter for a question only asked as "empty or not".
turso_row_count() {
    local db="$1" total=0 answered=1 table n
    have sqlite3 || return 1
    [ -f "$db" ] || return 1
    for table in user_profile_notes user_conversation_notes agent_reminders \
                 agent_workflows workflow_results sessions session_messages; do
        if n=$(sqlite3 -readonly "file:$db?immutable=1" \
                   "SELECT COUNT(*) FROM $table" 2>/dev/null) \
           && [ -n "$n" ]; then
            answered=0
            total=$((total + n))
        fi
    done
    [ "$answered" = 0 ] || return 1
    printf '%s' "$total"
}

# Echo KEY=VALUE pairs, one per line, for a given service. This is the single
# place ports and cross-service URLs are defined.
#
# Two collisions are resolved here and nowhere else: MCP_PORT and READ_ONLY are
# each used by three different services. Credential names now agree everywhere,
# so nothing is translated. pydantic-settings is case-insensitive, so the
# uppercase exports bind to the lowercase settings fields.
#
# Values are emitted one per line and read back line by line by collect_env
# below, so a value containing a newline would be split into fragments. That
# is why COINBASE_API_SECRET is kept on one line; the Coinbase server accepts the
# `\n`-escaped form Coinbase's own key file uses, as well as base64.
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
            emit COINBASE_API_KEY "$COINBASE_API_KEY"
            emit COINBASE_API_SECRET "$COINBASE_API_SECRET"
            ;;
        interactive-brokers-mcp)
            emit MCP_PORT "$IB_MCP_PORT"
            emit READ_ONLY "$IB_READ_ONLY"
            emit INTERACTIVE_BROKERS_PORTAL_BASE_URL "$IB_PORTAL_BASE_URL"
            ;;
        investpal-api|investpal-mcp)
            # These URLs need the /mcp path. All four MCP servers serve the
            # streamable-HTTP endpoint at /mcp and 404 at the root, and
            # InvestPal passes the value straight to the transport without
            # appending anything (dependencies.py, `connections`). Without the
            # path the client gets a 404, the session dies, and the only clue
            # is `McpError: Session terminated`. .mcp.json already gets this
            # right, which is why the cockpit works and only the backend
            # agent was affected.
            #
            # LLM_PROVIDER, LLM_MODEL and MARKET_DATA_MCP_SERVER_URL have no
            # defaults in InvestPal/config.py, so pydantic kills both processes
            # at import without them. All three are derivable, so they are
            # always supplied and never asked for during setup.
            emit LLM_PROVIDER "$LLM_PROVIDER"
            emit LLM_MODEL "$LLM_MODEL"
            emit MARKET_DATA_MCP_SERVER_URL "http://localhost:$MARKET_DATA_PORT/mcp"
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
                emit ALPACA_MCP_SERVER_URL "http://localhost:$ALPACA_MCP_PORT/mcp"
                emit COINBASE_MCP_SERVER_URL "http://localhost:$COINBASE_MCP_PORT/mcp"
            fi

            # Once the ~67MB model is cached, going offline skips a HuggingFace
            # metadata round-trip on every load. Only safe after a first fetch.
            if [ -d "$EMBEDDING_CACHE_DIR" ] && [ -n "$(ls -A "$EMBEDDING_CACHE_DIR" 2>/dev/null)" ]; then
                emit HF_HUB_OFFLINE 1
            fi
            ;;
        investpal-web)
            # Vite only exposes VITE_-prefixed variables to the bundle, so the
            # API URL is renamed here rather than passed under its own name.
            #
            # Everything emitted here is compiled into a browser bundle and is
            # therefore public. Never add a credential to this case.
            emit VITE_INVESTPAL_API_URL "http://localhost:$INVESTPAL_API_PORT"
            # Read by investpal-web/vite.config.ts, which sets strictPort so a
            # busy port fails loudly instead of silently moving to 5174, where
            # wait_for_service would never find it.
            emit PORT "$INVESTPAL_WEB_PORT"
            ;;
    esac
}

# Helper for service_env: skip empty values so a blank key never shadows a
# service's own default with an empty string.
emit() { [ -n "$2" ] && printf '%s=%s\n' "$1" "$2"; return 0; }

# Collect a service's fan-out pairs into ENV_PAIRS. Written as a read loop
# rather than mapfile so this keeps working on the bash 3.2 that ships with
# macOS. Lives here rather than in start.sh because ui.sh needs it too.
collect_env() {
    ENV_PAIRS=()
    local line
    while IFS= read -r line; do
        [ -n "$line" ] && ENV_PAIRS+=("$line")
    done < <(service_env "$1")
}

# ── Process lifecycle ────────────────────────────────────────────────────────

# start_service <name> <port> <dir> <cmd> [KEY=VALUE ...]
# Env pairs are passed as separate arguments so values containing spaces survive.
#
# The port is not used to launch anything — it is here so a port already bound by
# something we do not track is caught before we launch onto it. That case is not
# hypothetical: a `make stop` that deletes PID files without killing the processes
# leaves a whole generation running and untracked, and every service started after
# it dies instantly with EADDRINUSE.
start_service() {
    local name="$1"
    local port="$2"
    local dir="$3"
    local cmd="$4"
    shift 4
    local pid_file="$LOG_DIR/$name.pid"
    local log_file="$LOG_DIR/$name.log"

    if pid_alive "$name"; then
        echo -e "  ${YELLOW}$name${NC} already running (PID $(cat "$pid_file"))"
        return
    fi

    local owner
    owner=$(port_pid "$port")
    if [ -n "$owner" ]; then
        echo -e "  ${RED}Error:${NC} port $port is already bound by PID $owner, which no PID file tracks:"
        echo "    $(describe_pid "$owner")"
        echo "    This is a leftover from an earlier run. Run 'make stop' (it now reports"
        echo "    survivors), or kill $owner yourself, then 'make start' again."
        exit 1
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

# Shared failure path for wait_for_service: always show why it failed, since the
# reason is already sitting in the log and the caller would otherwise have to be
# told to go and read it.
service_failed() {
    local label="$1" name="$2" reason="$3" mode="${4:-required}"

    echo -e "  ${RED}$label $reason.${NC} Last lines of logs/$name.log:"
    tail -n 15 "$LOG_DIR/$name.log" 2>/dev/null | sed 's/^/    /'
    if [ "$mode" = "optional" ]; then
        echo -e "  ${YELLOW}Warning:${NC} continuing without $label."
        return 1
    fi
    echo -e "${RED}Error:${NC} $label is required. Aborting."
    exit 1
}

# wait_for_service <label> <name> <port> [retries] [mode]
# Three things must hold before a service counts as up: the PID we recorded is
# still alive, something is listening, and that listener belongs to us. Checking
# only the port (as this did previously) reports OK when an untracked process
# from an earlier run holds it and ours has already died — which is exactly how a
# fully broken stack printed "All services started".
#
# Fifth argument is "required" (default) or "optional". An optional service that
# never comes up returns 1 for the caller to handle instead of aborting startup.
wait_for_service() {
    local label="$1" name="$2" port="$3"
    local retries="${4:-30}" mode="${5:-required}"
    local owner

    echo -n "  Waiting for $label to be ready on port $port"
    for _ in $(seq 1 "$retries"); do
        if ! pid_alive "$name"; then
            echo -e " ${RED}FAILED${NC}"
            service_failed "$label" "$name" "exited during startup" "$mode" || return 1
        fi
        owner=$(port_pid "$port")
        if [ -n "$owner" ]; then
            if is_descendant "$owner" "$(service_pid "$name")"; then
                echo -e " ${GREEN}OK${NC}"
                return 0
            fi
            echo -e " ${RED}FAILED${NC}"
            service_failed "$label" "$name" \
                "did not get port $port: PID $owner holds it and is not part of $name" \
                "$mode" || return 1
        fi
        echo -n "."
        sleep 1
    done
    echo -e " ${RED}TIMEOUT${NC}"
    service_failed "$label" "$name" "did not start within ${retries}s" "$mode" || return 1
}

# Kill a process and all its descendants, deepest first, escalating to SIGKILL if
# any survive. Returns 1 if something is still alive at the end.
#
# The previous version fired one SIGTERM per PID and never looked back, so a
# process that ignored or outlived it survived while the caller deleted its PID
# file and reported success — the way a live service ends up untracked.
kill_tree() {
    local pid="$1" child survivor waited=0
    local tree=""

    # Snapshot the tree before killing anything: once the parents die the
    # pgrep -P links are gone and the grandchildren become unreachable.
    _collect_tree() {
        local p="$1" c
        for c in $(pgrep -P "$p" 2>/dev/null); do
            _collect_tree "$c"
        done
        tree="$tree $p"
    }
    _collect_tree "$pid"

    for child in $tree; do kill "$child" 2>/dev/null || true; done

    # Up to 5s of grace for a clean shutdown, then force it.
    while [ "$waited" -lt 10 ]; do
        survivor=false
        for child in $tree; do
            kill -0 "$child" 2>/dev/null && survivor=true
        done
        [ "$survivor" = false ] && return 0
        sleep 0.5
        waited=$((waited + 1))
    done

    for child in $tree; do
        kill -0 "$child" 2>/dev/null && kill -9 "$child" 2>/dev/null
    done
    sleep 0.5
    for child in $tree; do
        kill -0 "$child" 2>/dev/null && return 1
    done
    return 0
}

# ── Reporting ────────────────────────────────────────────────────────────────

# Every service this repo manages, as label|pid-name|port. The one place the set
# is enumerated — the table, the status view and the orphan sweep all read it, so
# adding a service means touching this list only.
service_rows() {
    echo "InvestPal REST API|investpal-api|$INVESTPAL_API_PORT"
    echo "InvestPal MCP App|investpal-mcp|$INVESTPAL_MCP_PORT"
    echo "MarketDataMcpServer|market-data-mcp|$MARKET_DATA_PORT"
    echo "AlpacaMcpServer|alpaca-mcp|$ALPACA_MCP_PORT"
    echo "CoinbaseMcpServer|coinbase-mcp|$COINBASE_MCP_PORT"
    if [ -d "$REPO_DIR/InteractiveBrokersMcpServer" ]; then
        echo "InteractiveBrokersMcpServer|interactive-brokers-mcp|$IB_MCP_PORT"
        echo "IB Client Portal Gateway|ib-gateway|$IB_GATEWAY_PORT"
    fi
    # Opt-in and unsupervised, so it is listed only when it is actually running
    # or when something still holds its port. Guarding on the directory instead
    # would be wrong: investpal-web/ is committed to this repo, so the test is
    # always true and every cockpit-only user would see a permanent "stopped"
    # row for a component they never asked for. The port_open half is what lets
    # report_foreign_ports name a dev server that outlived `make stop` after its
    # PID file is gone.
    if [ -f "$LOG_DIR/investpal-web.pid" ] || port_open "$INVESTPAL_WEB_PORT"; then
        echo "InvestPal Web UI|investpal-web|$INVESTPAL_WEB_PORT"
    fi
}

# One word for what a service is doing. "foreign" means the port is held by a
# process none of our PID files claims — a leftover from an earlier run, and the
# state that has to be visible rather than mistaken for "running". Returned
# uncoloured so callers can pad it to a column width before adding escapes.
service_state() {
    local name="$1" port="$2"
    if service_up "$name" "$port"; then
        echo "running"
    elif pid_alive "$name" && ! port_open "$port"; then
        echo "starting"
    elif port_open "$port"; then
        echo "foreign"
    else
        echo "stopped"
    fi
}

# One-line description of a PID for error messages. Elides the middle rather than
# the tail: these are interpreter invocations whose identifying part (main.py,
# apps.mcp_api.app) sits at the end of a very long absolute path.
describe_pid() {
    ps -o command= -p "$1" 2>/dev/null |
        awk '{ if (length($0) > 100) print substr($0,1,44) "…" substr($0, length($0)-53); else print }'
}

state_colour() {
    case "$1" in
        running) printf '%s' "$GREEN" ;;
        starting|foreign) printf '%s' "$YELLOW" ;;
        *) printf '%s' "$RED" ;;
    esac
}

# The services table, shared by start.sh and status.sh so the two can never
# drift. Reads ports from the loaded config, and reports state per row rather
# than listing every service unconditionally as if it were up.
service_table() {
    local label name port state
    printf "  %-28s %-6s %-9s %s\n" "Service" "Port" "State" "Log"
    echo "  ────────────────────────────────────────────────────────────────────────"
    while IFS='|' read -r label name port; do
        [ -n "$label" ] || continue
        state=$(service_state "$name" "$port")
        printf "  %-28s %-6s %b%-9s%b %s\n" \
            "$label" "$port" "$(state_colour "$state")" "$state" "$NC" "logs/$name.log"
    done <<EOF
$(service_rows)
EOF
}

# Anything still holding a service port with no PID file behind it. Printed after
# a stop so an untracked survivor is named there and then, instead of surfacing
# an hour later as EADDRINUSE inside a service log nobody is reading.
report_foreign_ports() {
    local label name port owner found=false
    while IFS='|' read -r label name port; do
        [ -n "$label" ] || continue
        pid_alive "$name" && continue
        owner=$(port_pid "$port")
        [ -n "$owner" ] || continue
        if [ "$found" = false ]; then
            echo ""
            echo -e "${YELLOW}Still listening after stop:${NC}"
            found=true
        fi
        echo "  port $port ($label) held by PID $owner"
        echo "    $(describe_pid "$owner")"
    done <<EOF
$(service_rows)
EOF
    if [ "$found" = true ]; then
        echo ""
        echo "  Nothing tracks these, so 'make stop' cannot reach them. Kill them by PID"
        echo "  before starting again, or 'make start' will refuse to launch onto the port."
    fi
}
