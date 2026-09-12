#!/usr/bin/env bash
# Read-only diagnosis of an InvestPal ecosystem install. Changes nothing.
# Exits non-zero if any check FAILs, so it is usable as a gate.
#
# Never prints a credential — secrets are reported only as set / not set.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

load_env

FAILURES=0
WARNINGS=0

group() { echo ""; echo -e "${BLUE}▸${NC} $1"; }
pass()  { printf "  %-34s ${GREEN}PASS${NC}  %s\n" "$1" "${2:-}"; }
info()  { printf "  %-34s ${DIM}INFO${NC}  %s\n" "$1" "${2:-}"; }
warns() { printf "  %-34s ${YELLOW}WARN${NC}  %s\n" "$1" "$2"; WARNINGS=$((WARNINGS + 1)); }
fails() { printf "  %-34s ${RED}FAIL${NC}  %s\n" "$1" "$2"; FAILURES=$((FAILURES + 1)); }
fix()   { echo -e "        ${DIM}→ $1${NC}"; }

version_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]; }

env_get() {
    local file="$1" key="$2" line=""
    [ -f "$file" ] || return 0
    line=$(grep -E "^[[:space:]]*${key}=" "$file" 2>/dev/null | tail -1) || true
    [ -z "$line" ] && return 0
    line="${line#*=}"
    line="${line%\"}"; line="${line#\"}"
    line="${line%\'}"; line="${line#\'}"
    printf '%s' "$line"
}

# ── Toolchain ────────────────────────────────────────────────────────────────

group "Toolchain"
for tool in git make uv curl nc python3; do
    if have "$tool"; then pass "$tool"; else fails "$tool" "not on PATH"; fi
done
# TEMPORARY — Phase A only. Go stopped being a prerequisite when market data
# moved to OpenBB; it matters again only while the legacy server is switched on.
if [ "$MARKET_DATA_LEGACY_ENABLED" = "true" ]; then
    if have go; then
        gov=$(go version | awk '{print $3}' | sed 's/^go//')
        if version_ge "$gov" "1.25"; then pass "go" "$gov (legacy market data)"
        else fails "go" "$gov, need 1.25+ for the legacy market-data server"; fi
    else
        fails "go" "not on PATH, and MARKET_DATA_LEGACY_ENABLED=true needs it"
        fix "install Go, or set MARKET_DATA_LEGACY_ENABLED=false in .env"
    fi
fi
have_java && pass "java" "$(java -version 2>&1 | head -1 | sed 's/.*"\(.*\)".*/\1/')" \
    || info "java" "no runtime (Interactive Brokers only)"
have_node && pass "node" "$(node -v 2>/dev/null)" \
    || info "node" "not installed (local web UI only)"

# ── Repositories ─────────────────────────────────────────────────────────────

group "Repositories"
for repo in InvestPal AlpacaMcpServer CoinbaseMcpServer; do
    if [ -d "$REPO_DIR/$repo" ]; then pass "$repo"; else
        fails "$repo" "not cloned"; fix "make setup"
    fi
done
if [ -d "$REPO_DIR/InteractiveBrokersMcpServer" ]; then
    pass "InteractiveBrokersMcpServer"
else
    info "InteractiveBrokersMcpServer" "not cloned (optional)"
fi

# Market data is no longer a cloned repo: it is a pinned venv this repo owns.
# start.sh refuses to launch without it, so a missing one is a failure, not a
# warning. Version drift matters too — the two instances are configured against
# openbb-mcp-server 1.4.1 flag semantics.
if [ -x "$(openbb_bin)" ]; then
    obb_ver=$("$REPO_DIR/.venvs/openbb/bin/python" -c \
        'import importlib.metadata as m; print(m.version("openbb-mcp-server"))' 2>/dev/null) || obb_ver=""
    case "$obb_ver" in
        1.4.1) pass "OpenBB venv" "openbb-mcp-server $obb_ver" ;;
        "")    warns "OpenBB venv" "present but the version could not be read" ;;
        *)     warns "OpenBB venv" "openbb-mcp-server $obb_ver, pinned to 1.4.1"
               fix "make install — the category and discovery flags are 1.4.1 semantics" ;;
    esac
else
    fails "OpenBB venv" "missing — market data cannot start"
    fix "make install"
fi

# The SessionStart hook runs `uv run --project InvestPal`, so an unsynced venv
# there breaks every Claude Code session in this directory, not just the backend.
if [ -d "$REPO_DIR/InvestPal/.venv" ]; then
    pass "InvestPal venv" "synced"
else
    fails "InvestPal venv" "missing — the SessionStart hook needs it"
    fix "make install"
fi

# ── Configuration ────────────────────────────────────────────────────────────

group "Configuration"
if [ -f "$ENV_FILE" ]; then
    pass ".env" "present"
else
    warns ".env" "absent — services fall back to their own .env files"
    fix "make setup"
fi

# Check the file, not the resolved value: load_env substitutes a default for a
# blank one, which is a rescue rather than something to report as healthy.
raw_provider=$(env_get "$ENV_FILE" LLM_PROVIDER)
raw_model=$(env_get "$ENV_FILE" LLM_MODEL)

if [ -f "$ENV_FILE" ] && [ -z "$raw_provider" ]; then
    warns "LLM_PROVIDER" "blank in .env — the fan-out substitutes '$LLM_PROVIDER'"
    fix "set it explicitly; InvestPal/config.py gives it no default of its own"
else
    case "$LLM_PROVIDER" in
        anthropic|openai|google) pass "LLM_PROVIDER" "$LLM_PROVIDER" ;;
        *) fails "LLM_PROVIDER" "'$LLM_PROVIDER' is not a valid provider"
           fix "use anthropic, openai or google" ;;
    esac
fi

if [ -f "$ENV_FILE" ] && [ -z "$raw_model" ]; then
    warns "LLM_MODEL" "blank in .env — the fan-out substitutes '$LLM_MODEL'"
    fix "set it explicitly; InvestPal/config.py gives it no default of its own"
else
    pass "LLM_MODEL" "$LLM_MODEL"
fi

# Free, registration-only, and the one market-data key that is not really
# optional: commodity spot prices and most Federal Reserve series have no other
# free provider, and middleware.py turns the resulting failure into a message
# the model reads rather than an error anyone sees.
if [ -n "$FRED_API_KEY" ]; then
    pass "FRED_API_KEY" "set"
else
    warns "FRED_API_KEY" "unset — commodities and most Fed series return nothing"
    fix "free key at https://fredaccount.stlouisfed.org/apikeys, then .env.secrets"
fi
if [ -n "$FMP_API_KEY" ]; then
    pass "FMP_API_KEY" "set"
else
    info "FMP_API_KEY" "unset — ratios, world news, estimates and peers unavailable"
    fix "optional; see docs/market-data.md for what it unlocks"
fi

# ── Backend agent ────────────────────────────────────────────────────────────
# No key at all is a perfectly good cockpit-only install, never a failure.

group "Backend agent (optional)"
key_for_provider() {
    case "$1" in
        openai) printf '%s' "$OPENAI_API_KEY" ;;
        google) printf '%s' "$GOOGLE_API_KEY" ;;
        *)      printf '%s' "$ANTHROPIC_API_KEY" ;;
    esac
}
if [ -z "$ANTHROPIC_API_KEY$OPENAI_API_KEY$GOOGLE_API_KEY" ]; then
    info "Provider key" "none set — backend agent disabled, cockpit unaffected"
else
    for setting in LLM_PROVIDER INVESTMENT_MANAGER_LLM_PROVIDER \
                   USER_CONTEXT_MEMORY_MANAGER_LLM_PROVIDER \
                   WORKFLOW_EXECUTION_AGENT_LLM_PROVIDER; do
        provider="${!setting:-anthropic}"
        if [ -n "$(key_for_provider "$provider")" ]; then
            pass "$setting" "$provider"
        else
            warns "$setting" "$provider selected but its key is unset"
            fix "requests using this agent fail at call time; add the key to .env.secrets"
        fi
    done
fi

# ── Drift in per-service .env files ──────────────────────────────────────────
# pydantic-settings applies extra="forbid" to keys found in a dotenv file, so an
# unknown key there is a hard startup failure, not a warning.

group "Per-service config drift"
lint_service_env() { # lint_service_env DIR
    local dir="$1" env="$REPO_DIR/$1/.env" cfg="$REPO_DIR/$1/config.py"
    [ -f "$env" ] || { info "$dir/.env" "absent (root config is authoritative)"; return; }
    [ -f "$cfg" ] || return

    local fields unknown=""
    fields=$(grep -oE '^[[:space:]]+[A-Za-z_][A-Za-z_0-9]*[[:space:]]*:' "$cfg" \
             | tr -d ' :' | tr 'A-Z' 'a-z')
    local key
    while IFS= read -r key; do
        [ -z "$key" ] && continue
        printf '%s\n' "$fields" | grep -qx "$(printf '%s' "$key" | tr 'A-Z' 'a-z')" || unknown="$unknown $key"
    done < <(grep -oE '^[[:space:]]*[A-Za-z_][A-Za-z_0-9]*=' "$env" | tr -d ' =')

    if [ -n "$unknown" ]; then
        fails "$dir/.env" "unknown key(s):$unknown"
        fix "extra=\"forbid\" makes this a startup crash; delete the key or the file"
    else
        warns "$dir/.env" "still present but superseded by the root config"
        fix "rename it to .env.superseded to avoid the two disagreeing"
    fi
}
for d in InvestPal AlpacaMcpServer CoinbaseMcpServer InteractiveBrokersMcpServer; do
    [ -d "$REPO_DIR/$d" ] && lint_service_env "$d"
done

# ── Ports ────────────────────────────────────────────────────────────────────

group "Ports"
if [ -f "$REPO_DIR/.mcp.json" ] && have python3; then
    mismatch=$(python3 - "$REPO_DIR/.mcp.json" <<PY
import json, re, sys
expected = {
    "investpal": "$INVESTPAL_MCP_PORT",
    # Claude clients get the discovery instance, not the static one.
    "market-data": "$MARKET_DATA_DISCOVERY_PORT",
    "alpaca": "$ALPACA_MCP_PORT",
    "coinbase": "$COINBASE_MCP_PORT",
    "interactive-brokers": "$IB_MCP_PORT",
}
with open(sys.argv[1]) as fh:
    servers = json.load(fh).get("mcpServers", {})
for name, want in expected.items():
    entry = servers.get(name)
    if not entry:
        continue
    found = re.search(r":(\d+)/", entry.get("url", ""))
    if found and found.group(1) != want:
        print(f"{name}: .mcp.json says {found.group(1)}, .env says {want}")
PY
)
    if [ -n "$mismatch" ]; then
        while IFS= read -r line; do
            fails "port mismatch" "$line"
        done <<< "$mismatch"
        fix "Claude Code reads .mcp.json and cannot see .env; make them agree"
    else
        pass "Ports" ".env agrees with .mcp.json"
    fi
fi

for entry in "InvestPal REST API:$INVESTPAL_API_PORT:investpal-api" \
             "InvestPal MCP App:$INVESTPAL_MCP_PORT:investpal-mcp" \
             "Market Data (OpenBB):$MARKET_DATA_PORT:market-data-mcp" \
             "Market Data Discovery:$MARKET_DATA_DISCOVERY_PORT:market-data-discovery-mcp" \
             "AlpacaMcpServer:$ALPACA_MCP_PORT:alpaca-mcp" \
             "CoinbaseMcpServer:$COINBASE_MCP_PORT:coinbase-mcp"; do
    label="${entry%%:*}"; rest="${entry#*:}"; port="${rest%%:*}"; svc="${rest#*:}"
    # Skip when a PID file exists — that is our own orphan, which check_service
    # reports below with a more precise diagnosis.
    if port_open "$port" && ! pid_alive "$svc" && [ ! -f "$LOG_DIR/$svc.pid" ]; then
        warns "port $port" "in use by something that is not $label"
        fix "stop the other process or change the port in .env"
    fi
done

# ── Runtime ──────────────────────────────────────────────────────────────────

group "Running services"
check_service() { # check_service LABEL PID_NAME PORT [mcp]
    local label="$1" name="$2" port="$3" is_mcp="${4:-}"
    if ! pid_alive "$name"; then
        if port_open "$port"; then
            # An orphan: the supervising subshell died but its child kept the
            # port. `make stop` will drop the stale PID file and leave the child
            # running, so the next `make start` cannot bind. Serving traffic
            # today, guaranteed to break tomorrow.
            local owner
            owner=$(lsof -nP -iTCP:"$port" -sTCP:LISTEN -t 2>/dev/null | head -1)
            fails "$label" "orphaned on port $port — PID file is stale"
            fix "kill ${owner:-the listening process}, then 'make start'"
        else
            fails "$label" "not running"
            fix "make start"
        fi
        return
    fi
    if ! port_open "$port"; then
        fails "$label" "process alive but port $port is closed"
        fix "check logs/$name.log"
        return
    fi
    if [ "$is_mcp" = "mcp" ] && have curl; then
        local code
        code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 \
               -X POST "http://127.0.0.1:$port/mcp" \
               -H 'Content-Type: application/json' \
               -H 'Accept: application/json, text/event-stream' \
               -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"doctor","version":"1"}}}' \
               2>/dev/null) || code=000
        if [ "$code" = "200" ]; then pass "$label" "port $port, MCP responding"
        else warns "$label" "port $port open but MCP returned $code"; fi
    else
        pass "$label" "port $port"
    fi
}
check_service "InvestPal REST API" investpal-api "$INVESTPAL_API_PORT"
check_service "InvestPal MCP App"  investpal-mcp "$INVESTPAL_MCP_PORT" mcp
check_service "Market Data (OpenBB)" market-data-mcp "$MARKET_DATA_PORT" mcp
check_service "Market Data Discovery" market-data-discovery-mcp "$MARKET_DATA_DISCOVERY_PORT" mcp
if [ "$MARKET_DATA_LEGACY_ENABLED" = "true" ]; then
    # TEMPORARY — Phase A only.
    check_service "Market Data (legacy Go)" market-data-legacy "$MARKET_DATA_LEGACY_PORT" mcp
fi
check_service "AlpacaMcpServer"    alpaca-mcp "$ALPACA_MCP_PORT" mcp
check_service "CoinbaseMcpServer"  coinbase-mcp "$COINBASE_MCP_PORT" mcp
if [ -d "$REPO_DIR/InteractiveBrokersMcpServer" ]; then
    check_service "InteractiveBrokersMcpServer" interactive-brokers-mcp "$IB_MCP_PORT" mcp
fi

# ── Database ─────────────────────────────────────────────────────────────────

group "Database"
# Without a root .env the services still read their own, so look there too
# rather than reporting sync as unconfigured when it is very much configured.
if [ -z "$TURSO_SYNC_URL" ]; then
    TURSO_SYNC_URL=$(env_get "$REPO_DIR/InvestPal/.env" TURSO_SYNC_URL)
fi
if [ -n "$TURSO_SYNC_URL" ]; then
    # State comes from the files (lib.sh turso_state), exactly as InvestPal's
    # db_state() decides it, rather than from grepping `turso_status` output for
    # state names it never prints. That grep matched nothing and fell through to
    # the default branch, so a database that was stopping both services dead was
    # reported as "synced".
    db="$(turso_db_path)"
    case "$(turso_state)" in
        synced)
            pass "Turso Cloud sync" "synced"
            ;;
        local_only)
            # Whether the file holds anything decides which command is right, and
            # naming only one of them is what sent an empty database down the
            # first_push path with no way back but deleting it by hand.
            rows=$(turso_row_count "$db") || rows=""
            case "$rows" in
                "") held="" ;;
                1)  held=" (1 row)" ;;
                *)  held=" ($rows rows)" ;;
            esac
            if [ "$rows" = "0" ]; then
                fails "Turso Cloud sync" "local database never pushed, and it is empty"
                fix "make turso_first_pull — take the cloud copy (the empty file is moved aside)"
                fix "make turso_first_push — or seed the cloud from this machine instead"
            else
                fails "Turso Cloud sync" "local database never pushed$held"
                fix "make turso_first_push — seed the cloud from this machine"
                fix "make turso_first_pull FORCE=1 — or discard it for the cloud copy"
            fi
            fix "InvestPal will not start until one of those has run"
            ;;
        broken)
            fails "Turso Cloud sync" "sync metadata with no database file"
            fix "make turso_first_pull — it moves the leftover sidecars aside itself"
            ;;
        fresh)
            fails "Turso Cloud sync" "no local database"
            fix "make turso_first_pull"
            ;;
    esac
else
    info "Turso Cloud sync" "not configured (local file only)"
fi

if [ "$EMBEDDING_ENABLED" = "false" ]; then
    info "Semantic search" "disabled by EMBEDDING_ENABLED=false"
elif [ -d "$EMBEDDING_CACHE_DIR" ] && [ -n "$(ls -A "$EMBEDDING_CACHE_DIR" 2>/dev/null)" ]; then
    pass "Embedding model" "cached"
else
    warns "Embedding model" "not cached — first search downloads ~67MB"
fi

# ── Interactive Brokers ──────────────────────────────────────────────────────

if [ -d "$REPO_DIR/InteractiveBrokersMcpServer" ]; then
    group "Interactive Brokers"
    gw="$REPO_DIR/InteractiveBrokersMcpServer/ib_clientportal/bin/run.sh"
    have_java && pass "java" || { warns "java" "no runtime"; fix "the gateway needs a Java 1.8+ runtime"; }
    if [ -f "$gw" ]; then pass "Client Portal Gateway" "installed"; else
        warns "Client Portal Gateway" "not installed"
        fix "unpack IB's gateway into InteractiveBrokersMcpServer/ib_clientportal/"
    fi
    if port_open "$IB_GATEWAY_PORT"; then
        auth=$(curl -sk --max-time 3 "https://localhost:$IB_GATEWAY_PORT/v1/api/iserver/auth/status" 2>/dev/null) || auth=""
        case "$auth" in
            *'"authenticated":true'*) pass "Gateway session" "authenticated" ;;
            *) warns "Gateway session" "not authenticated"
               fix "open https://localhost:$IB_GATEWAY_PORT and log in" ;;
        esac
    else
        info "Gateway session" "gateway not running"
    fi
fi

# ── Secrets ──────────────────────────────────────────────────────────────────
# Values are never printed, only their presence.

group "Secrets"
if [ -f "$SECRETS_FILE" ]; then
    perms=$(stat -f '%Lp' "$SECRETS_FILE" 2>/dev/null || stat -c '%a' "$SECRETS_FILE" 2>/dev/null)
    if [ "$perms" = "600" ]; then pass ".env.secrets" "mode 600"; else
        warns ".env.secrets" "mode $perms"
        fix "chmod 600 .env.secrets"
    fi
    if git -C "$REPO_DIR" check-ignore -q .env.secrets 2>/dev/null; then
        pass ".env.secrets" "gitignored"
    else
        fails ".env.secrets" "not gitignored"
        fix "add .env.secrets to .gitignore before committing anything"
    fi
    if git -C "$REPO_DIR" ls-files --error-unmatch .env.secrets >/dev/null 2>&1; then
        fails ".env.secrets" "tracked by git — credentials are in your history"
        fix "git rm --cached .env.secrets and rotate the keys"
    fi
else
    info ".env.secrets" "absent — no credentials configured"
fi

if grep -q '"deny"' "$REPO_DIR/.claude/settings.json" 2>/dev/null; then
    pass "Agent deny rules" "present in .claude/settings.json"
else
    warns "Agent deny rules" "absent — the agent can read .env.secrets"
    fix "restore the permissions.deny block in .claude/settings.json"
fi

# Brokerage keys are read by the broker servers from their own process
# environment, which start.sh supplies. Nothing needs them in this shell, so the
# only question is whether the file has them.
for pair in "ALPACA_API_KEY:Alpaca:alpaca-mcp" "COINBASE_API_KEY:Coinbase:coinbase-mcp"; do
    IFS=: read -r var label service <<<"$pair"
    if [ -n "$(env_get "$SECRETS_FILE" "$var")" ]; then
        pass "$label credentials" "configured"
        # The failure mode that replaced a missing header: a server that started
        # without credentials comes up healthy and simply registers no tools, so
        # the port check above cannot see it. The server says so on startup.
        if [ -f "$LOG_DIR/$service.log" ] \
           && tail -50 "$LOG_DIR/$service.log" | grep -q "registering no tools"; then
            warns "$label tools" "server started without credentials"
            fix "make stop && make start, then check logs/$service.log"
        fi
    else
        info "$label credentials" "not configured"
    fi
done

# ── Local web UI (optional) ──────────────────────────────────────────────────
# Never fails. `make ui` is opt-in, so its absence is not a fault, and doctor
# exits non-zero on any FAIL.

group "Local web UI (optional)"
if ! have_node; then
    info "node" "not installed — 'make ui' unavailable, nothing else affected"
elif [ -d "$REPO_DIR/investpal-web/node_modules" ]; then
    pass "investpal-web deps" "installed"
else
    info "investpal-web deps" "not installed — 'make ui' installs them on first run"
fi

if pid_alive investpal-web; then
    if port_open "$INVESTPAL_WEB_PORT"; then
        pass "investpal-web" "port $INVESTPAL_WEB_PORT"
    else
        warns "investpal-web" "process alive but port $INVESTPAL_WEB_PORT is closed"
        fix "check logs/investpal-web.log"
    fi
elif port_open "$INVESTPAL_WEB_PORT"; then
    warns "investpal-web" "port $INVESTPAL_WEB_PORT held by a process no PID file tracks"
    fix "kill it, or change INVESTPAL_WEB_PORT in .env"
else
    info "investpal-web" "not running"
fi

# The single most useful thing doctor can say about this app. `make setup`
# defaults the backend agent to no, so on a stock install every view works
# except chat, which 500s — and InvestPal sends no CORS headers on a 500, so
# the browser cannot even show the status.
if [ -z "$ANTHROPIC_API_KEY$OPENAI_API_KEY$GOOGLE_API_KEY" ]; then
    info "Web UI chat" "no provider key — the chat view will fail, other views work"
    fix "chat calls POST /chat, which runs InvestPal's own agent; see .env.secrets"
fi

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
if [ "$FAILURES" -gt 0 ]; then
    echo -e "${RED}$FAILURES failed${NC}, $WARNINGS warnings."
    exit 1
elif [ "$WARNINGS" -gt 0 ]; then
    echo -e "${GREEN}No failures${NC}, $WARNINGS warnings."
else
    echo -e "${GREEN}Everything checks out.${NC}"
fi
