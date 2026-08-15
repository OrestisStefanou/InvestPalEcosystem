#!/usr/bin/env bash
# One-command bootstrap: prerequisites, clone, install, configure, database,
# start. Safe to re-run — it only does what is still missing.
#
#   YES=1    take every default, ask nothing
#   FORCE=1  re-prompt even for values already configured
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

YES="${YES:-0}"
FORCE="${FORCE:-0}"
EXAMPLE_ENV="$REPO_DIR/.env.example"
EXAMPLE_SECRETS="$REPO_DIR/.env.secrets.example"
IMPORTED_FROM=()

# Nothing to read answers from means nothing to ask.
if [ "$YES" != "1" ] && [ ! -t 0 ] && [ ! -e /dev/tty ]; then
    YES=1
fi

# ── Output helpers ───────────────────────────────────────────────────────────

phase() { echo ""; echo -e "${BLUE}▸${NC} $1"; }
ok()    { printf "  %-30s ${GREEN}%s${NC}\n" "$1" "${2:-OK}"; }
warn()  { printf "  %-30s ${YELLOW}%s${NC}\n" "$1" "$2"; }
bad()   { printf "  %-30s ${RED}%s${NC}\n" "$1" "$2"; }
note()  { echo -e "    ${DIM}$1${NC}"; }

# ── Prompting ────────────────────────────────────────────────────────────────

ask() { # ask VAR "question" "default"
    local __var="$1" question="$2" def="$3" ans=""
    if [ "$YES" = "1" ]; then
        printf -v "$__var" '%s' "$def"
        return
    fi
    read -r -p "  $question [$def]: " ans < /dev/tty || ans=""
    [ -z "$ans" ] && ans="$def"
    printf -v "$__var" '%s' "$ans"
}

ask_secret() { # ask_secret VAR "question"
    local __var="$1" question="$2" ans=""
    if [ "$YES" = "1" ]; then
        printf -v "$__var" '%s' ""
        return
    fi
    # -s so the value never reaches the scrollback.
    read -r -s -p "  $question: " ans < /dev/tty || ans=""
    echo ""
    printf -v "$__var" '%s' "$ans"
}

ask_yn() { # ask_yn "question" default_y_or_n  -> 0 for yes
    local question="$1" def="$2" ans=""
    if [ "$YES" = "1" ]; then
        [ "$def" = "y" ]
        return
    fi
    local hint="y/N"
    [ "$def" = "y" ] && hint="Y/n"
    read -r -p "  $question [$hint]: " ans < /dev/tty || ans=""
    [ -z "$ans" ] && ans="$def"
    case "$ans" in [yY]*) return 0 ;; *) return 1 ;; esac
}

# ── dotenv read/write ────────────────────────────────────────────────────────

env_get() { # env_get FILE KEY
    local file="$1" key="$2" line=""
    [ -f "$file" ] || return 0
    line=$(grep -E "^[[:space:]]*${key}=" "$file" 2>/dev/null | tail -1) || true
    [ -z "$line" ] && return 0
    line="${line#*=}"
    line="${line%\"}"; line="${line#\"}"
    line="${line%\'}"; line="${line#\'}"
    printf '%s' "$line"
}

set_kv() { # set_kv FILE KEY VALUE
    local file="$1" key="$2" value="$3" tmp
    # Quote anything the shell would mis-parse when the file is sourced.
    case "$value" in
        *[[:space:]\(\)\#\'\"]*) value="\"$value\"" ;;
    esac
    if grep -qE "^[[:space:]]*#?[[:space:]]*${key}=" "$file" 2>/dev/null; then
        tmp="$file.tmp.$$"
        awk -v k="$key" -v v="$value" '
            $0 ~ "^[[:space:]]*#?[[:space:]]*" k "=" && !done { print k "=" v; done=1; next }
            { print }
        ' "$file" > "$tmp"
        mv "$tmp" "$file"
    else
        printf '%s=%s\n' "$key" "$value" >> "$file"
    fi
}

# Copy a key from a service .env into one of the root files, if it has a value.
import_kv() { # import_kv SRC_FILE SRC_KEY DEST_FILE DEST_KEY
    local value
    value=$(env_get "$1" "$2")
    [ -z "$value" ] && return 0
    set_kv "$3" "$4" "$value"
    return 0
}

version_ge() { # version_ge HAVE WANT
    [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]
}

# ── 1. Prerequisites ─────────────────────────────────────────────────────────

hint() {
    case "$(uname -s)" in
        Darwin) echo "brew install $1" ;;
        *)      echo "apt install $1" ;;
    esac
}

check_prereqs() {
    phase "Checking prerequisites"
    local missing=0

    for tool in git make curl nc; do
        if have "$tool"; then
            ok "$tool" "OK"
        else
            bad "$tool" "missing"
            note "$(hint "$tool")"
            missing=1
        fi
    done

    # uv provides the Python 3.13 runtimes for the four Python services, so the
    # system python3 only needs to exist for this script's JSON edits.
    if have uv; then
        ok "uv" "$(uv --version 2>/dev/null | awk '{print $2}')"
    else
        bad "uv" "missing"
        note "curl -LsSf https://astral.sh/uv/install.sh | sh"
        missing=1
    fi

    if have go; then
        local gov
        gov=$(go version | awk '{print $3}' | sed 's/^go//')
        if version_ge "$gov" "1.25"; then
            ok "go" "$gov"
        else
            bad "go" "$gov, need 1.25+"
            missing=1
        fi
    else
        bad "go" "missing"
        note "$(hint go)"
        missing=1
    fi

    have python3 && ok "python3" "$(python3 -V 2>&1 | awk '{print $2}')" || {
        bad "python3" "missing"; missing=1;
    }

    # Optional: only the Interactive Brokers gateway needs it.
    if have_java; then
        ok "java" "OK"
    else
        warn "java" "missing (Interactive Brokers only)"
    fi

    if [ "$missing" -ne 0 ]; then
        echo ""
        echo -e "${RED}Install the missing prerequisites above, then run 'make setup' again.${NC}"
        exit 1
    fi
}

# ── 2/3. Clone and install ───────────────────────────────────────────────────

clone_repos() {
    phase "Cloning repositories"
    make -C "$REPO_DIR" --no-print-directory clone | sed 's/^/  /'
}

install_deps() {
    phase "Installing dependencies"
    make -C "$REPO_DIR" --no-print-directory install | sed 's/^/  /'
}

# ── 4. Configuration ─────────────────────────────────────────────────────────

import_service_env() {
    local investpal="$REPO_DIR/InvestPal/.env"
    local marketdata="$REPO_DIR/MarketDataMcpServer/.env"
    local alpaca="$REPO_DIR/AlpacaMcpServer/.env"
    local coinbase="$REPO_DIR/CoinbaseMcpServer/.env"
    local ib="$REPO_DIR/InteractiveBrokersMcpServer/.env"

    if [ -f "$investpal" ]; then
        ok "InvestPal/.env" "$(grep -cE '^[A-Za-z]' "$investpal") keys imported"
        import_kv "$investpal" LLM_PROVIDER              "$ENV_FILE" LLM_PROVIDER
        import_kv "$investpal" LLM_MODEL                 "$ENV_FILE" LLM_MODEL
        import_kv "$investpal" TURSO_DB_PATH             "$ENV_FILE" TURSO_DB_PATH
        import_kv "$investpal" MCP_APP_SERVER_PORT       "$ENV_FILE" INVESTPAL_MCP_PORT
        import_kv "$investpal" TURSO_SYNC_URL            "$ENV_FILE" TURSO_SYNC_URL
        import_kv "$investpal" TURSO_SYNC_CLIENT_NAME    "$ENV_FILE" TURSO_SYNC_CLIENT_NAME
        import_kv "$investpal" EMBEDDING_ENABLED         "$ENV_FILE" EMBEDDING_ENABLED
        import_kv "$investpal" ANTHROPIC_API_KEY         "$SECRETS_FILE" ANTHROPIC_API_KEY
        import_kv "$investpal" OPENAI_API_KEY            "$SECRETS_FILE" OPENAI_API_KEY
        import_kv "$investpal" GOOGLE_API_KEY            "$SECRETS_FILE" GOOGLE_API_KEY
        import_kv "$investpal" TURSO_SYNC_AUTH_TOKEN     "$SECRETS_FILE" TURSO_SYNC_AUTH_TOKEN
        IMPORTED_FROM+=("$investpal")
    fi

    if [ -f "$marketdata" ]; then
        ok "MarketDataMcpServer/.env" "$(grep -cE '^[A-Za-z]' "$marketdata") keys imported"
        import_kv "$marketdata" PORT                 "$ENV_FILE" MARKET_DATA_PORT
        import_kv "$marketdata" CACHE_TTL            "$ENV_FILE" CACHE_TTL
        # A CoinGecko key is a credential, so it goes in the protected file.
        import_kv "$marketdata" COIN_GECKO_API_KEY   "$SECRETS_FILE" COIN_GECKO_API_KEY
        import_kv "$marketdata" SEC_EDGAR_USER_AGENT "$ENV_FILE" SEC_EDGAR_USER_AGENT
        if [ -n "$(env_get "$marketdata" ALPHA_VANTAGE_API_KEY)" ]; then
            note "ALPHA_VANTAGE_API_KEY dropped — no Go source references it any more"
        fi
        IMPORTED_FROM+=("$marketdata")
    fi

    if [ -f "$alpaca" ]; then
        ok "AlpacaMcpServer/.env" "imported"
        import_kv "$alpaca" MCP_PORT             "$ENV_FILE" ALPACA_MCP_PORT
        import_kv "$alpaca" READ_ONLY            "$ENV_FILE" ALPACA_READ_ONLY
        import_kv "$alpaca" ALPACA_API_BASE_URL  "$ENV_FILE" ALPACA_API_BASE_URL
        import_kv "$alpaca" ALPACA_API_KEY       "$SECRETS_FILE" ALPACA_API_KEY
        import_kv "$alpaca" ALPACA_API_SECRET    "$SECRETS_FILE" ALPACA_API_SECRET
        IMPORTED_FROM+=("$alpaca")
    fi

    if [ -f "$coinbase" ]; then
        ok "CoinbaseMcpServer/.env" "imported"
        import_kv "$coinbase" MCP_PORT            "$ENV_FILE" COINBASE_MCP_PORT
        import_kv "$coinbase" READ_ONLY           "$ENV_FILE" COINBASE_READ_ONLY
        import_kv "$coinbase" COINBASE_KEY_NAME   "$SECRETS_FILE" COINBASE_API_KEY
        import_kv "$coinbase" COINBASE_KEY_SECRET "$SECRETS_FILE" COINBASE_API_SECRET
        IMPORTED_FROM+=("$coinbase")
    fi

    if [ -f "$ib" ]; then
        ok "InteractiveBrokersMcpServer/.env" "imported"
        import_kv "$ib" MCP_PORT  "$ENV_FILE" IB_MCP_PORT
        import_kv "$ib" READ_ONLY "$ENV_FILE" IB_READ_ONLY
        import_kv "$ib" INTERACTIVE_BROKERS_PORTAL_BASE_URL "$ENV_FILE" IB_PORTAL_BASE_URL
        IMPORTED_FROM+=("$ib")
    fi
}

retire_service_env() {
    [ "${#IMPORTED_FROM[@]}" -eq 0 ] && return 0
    echo ""
    note "These files are now redundant: the root config is exported into each"
    note "service at start time and takes precedence. Leaving them risks the two"
    note "disagreeing, and a stale key in one is a hard startup failure."
    if ask_yn "Rename them to .env.superseded?" "y"; then
        local f
        for f in "${IMPORTED_FROM[@]}"; do
            [ -f "$f" ] && mv "$f" "$f.superseded" && ok "$(basename "$(dirname "$f")")/.env" "renamed"
        done
    fi
}

configure() {
    phase "Configuration"

    if [ -f "$ENV_FILE" ] && [ "$FORCE" != "1" ]; then
        ok ".env" "already configured"
    else
        [ -f "$ENV_FILE" ] || cp "$EXAMPLE_ENV" "$ENV_FILE"
        [ -f "$SECRETS_FILE" ] || cp "$EXAMPLE_SECRETS" "$SECRETS_FILE"
        chmod 600 "$SECRETS_FILE"

        import_service_env

        # The only question with no usable default. EDGAR 403s a User-Agent that
        # carries no contact address.
        local current email
        current=$(env_get "$ENV_FILE" SEC_EDGAR_USER_AGENT)
        case "$current" in
            ""|*you@example.com*|*contact@example.com*)
                echo ""
                ask email "Contact email for SEC EDGAR (Enter to skip)" ""
                if [ -n "$email" ]; then
                    set_kv "$ENV_FILE" SEC_EDGAR_USER_AGENT "InvestPal/1.0 ($email)"
                    ok "SEC_EDGAR_USER_AGENT" "set"
                else
                    warn "SEC_EDGAR_USER_AGENT" "using placeholder"
                    note "SEC filings may return 403 until you set a real address in .env"
                fi
                ;;
        esac

        retire_service_env
        ok ".env" "written"
        ok ".env.secrets" "written (mode 600)"
    fi

    [ -f "$SECRETS_FILE" ] && chmod 600 "$SECRETS_FILE"
    load_env
}

# ── 5. Optional integrations ─────────────────────────────────────────────────

enable_mcp_server() { # move a server from disabled to enabled in settings.local.json
    local server="$1" file="$REPO_DIR/.claude/settings.local.json"
    [ -f "$file" ] || return 0
    python3 - "$file" "$server" <<'PY'
import json, sys
path, server = sys.argv[1], sys.argv[2]
with open(path) as fh:
    data = json.load(fh)
enabled = data.setdefault("enabledMcpjsonServers", [])
disabled = data.setdefault("disabledMcpjsonServers", [])
if server in disabled:
    disabled.remove(server)
if server not in enabled:
    enabled.append(server)
with open(path, "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
PY
}

configure_backend_agent() {
    local existing
    existing=$(env_get "$SECRETS_FILE" ANTHROPIC_API_KEY)$(env_get "$SECRETS_FILE" OPENAI_API_KEY)$(env_get "$SECRETS_FILE" GOOGLE_API_KEY)
    if [ -n "$existing" ] && [ "$FORCE" != "1" ]; then
        ok "Backend agent" "already has a provider key"
        return 0
    fi

    echo ""
    note "The cockpit does not need an LLM key — there, Claude Code is the LLM."
    note "A key is only for InvestPal's own agent: the /chat REST endpoint, the"
    note "Streamlit dev UI, and workflows the backend runs itself."
    if ! ask_yn "Enable InvestPal's own backend agent?" "n"; then
        ok "Backend agent" "skipped"
        return 0
    fi

    local provider key var
    ask provider "Provider (anthropic | openai | google)" "anthropic"
    case "$provider" in
        openai) var=OPENAI_API_KEY ;;
        google) var=GOOGLE_API_KEY ;;
        *)      var=ANTHROPIC_API_KEY; provider=anthropic ;;
    esac
    ask_secret key "$var"
    if [ -n "$key" ]; then
        set_kv "$SECRETS_FILE" "$var" "$key"
        set_kv "$ENV_FILE" LLM_PROVIDER "$provider"
        ok "Backend agent" "$provider"
    else
        warn "Backend agent" "no key entered, skipped"
    fi
}

configure_brokers() {
    local key secret

    if [ -z "$(env_get "$SECRETS_FILE" ALPACA_API_KEY)" ] || [ "$FORCE" = "1" ]; then
        if ask_yn "Connect Alpaca (stocks and ETFs)?" "n"; then
            ask_secret key "ALPACA_API_KEY"
            ask_secret secret "ALPACA_API_SECRET"
            if [ -n "$key" ]; then
                set_kv "$SECRETS_FILE" ALPACA_API_KEY "$key"
                set_kv "$SECRETS_FILE" ALPACA_API_SECRET "$secret"
                enable_mcp_server alpaca
                ok "Alpaca" "configured and enabled"
                note "Paper trading by default; change ALPACA_API_BASE_URL in .env for live."
            fi
        fi
    else
        ok "Alpaca" "already configured"
    fi

    if [ -z "$(env_get "$SECRETS_FILE" COINBASE_API_KEY)" ] || [ "$FORCE" = "1" ]; then
        if ask_yn "Connect Coinbase (crypto)?" "n"; then
            ask_secret key "COINBASE_API_KEY (the key name)"
            ask_secret secret "COINBASE_API_SECRET (base64-encoded)"
            if [ -n "$key" ]; then
                set_kv "$SECRETS_FILE" COINBASE_API_KEY "$key"
                set_kv "$SECRETS_FILE" COINBASE_API_SECRET "$secret"
                enable_mcp_server coinbase
                ok "Coinbase" "configured and enabled"
            fi
        fi
    else
        ok "Coinbase" "already configured"
    fi

    # Interactive Brokers needs no keys, only its gateway.
    if [ -d "$REPO_DIR/InteractiveBrokersMcpServer" ]; then
        local gw="$REPO_DIR/InteractiveBrokersMcpServer/ib_clientportal/bin/run.sh"
        if [ -f "$gw" ]; then
            ok "Interactive Brokers" "gateway installed"
        else
            warn "Interactive Brokers" "gateway not installed"
            note "IB uses a browser login, not API keys. To enable it:"
            note "  1. Download the Client Portal API gateway from Interactive Brokers"
            note "  2. Unpack it into InteractiveBrokersMcpServer/ib_clientportal/"
            note "  3. Re-run 'make start', then log in at https://localhost:$IB_GATEWAY_PORT"
            have_java || note "  Also install a Java 1.8+ runtime — $(hint openjdk)"
        fi
    fi
}

optional_integrations() {
    phase "Optional integrations"
    configure_backend_agent
    configure_brokers
}

# ── 6. Database and embedding model ──────────────────────────────────────────

prepare_data() {
    phase "Database and search index"

    if [ -n "$TURSO_SYNC_URL" ]; then
        local state
        state=$(make -C "$REPO_DIR/InvestPal" --no-print-directory turso_status 2>&1) || true
        case "$state" in
            *local_only*)
                warn "Turso Cloud sync" "local database not yet pushed"
                note "Both InvestPal processes refuse to start until this is done."
                ask_yn "Run 'make turso_first_push' now?" "y" && \
                    make -C "$REPO_DIR" --no-print-directory turso_first_push
                ;;
            *fresh*)
                warn "Turso Cloud sync" "no local database yet"
                ask_yn "Run 'make turso_first_pull' now?" "y" && \
                    make -C "$REPO_DIR" --no-print-directory turso_first_pull
                ;;
            *broken*)
                bad "Turso Cloud sync" "inconsistent local state"
                note "Move the investpal.db-* sidecars aside, then run 'make turso_first_pull'."
                note "See InvestPal/docs/turso_sync.md."
                ;;
            *)
                ok "Turso Cloud sync" "ready"
                ;;
        esac
    else
        ok "Database" "local file, created on first start"
    fi

    if [ "$EMBEDDING_ENABLED" = "false" ]; then
        ok "Semantic search" "disabled"
        return 0
    fi

    if [ -d "$EMBEDDING_CACHE_DIR" ] && [ -n "$(ls -A "$EMBEDDING_CACHE_DIR" 2>/dev/null)" ]; then
        ok "Embedding model" "cached"
    else
        echo -n "  Downloading embedding model (~67MB, once)"
        if (cd "$REPO_DIR/InvestPal" && uv run python3 -c \
            'from repos.embeddings import _get_model; _get_model()' >/dev/null 2>&1); then
            echo -e " ${GREEN}OK${NC}"
        else
            echo -e " ${YELLOW}skipped${NC}"
            note "It will download on first use instead. Semantic search still works."
        fi
    fi
}

# ── 7. Start ─────────────────────────────────────────────────────────────────

start_stack() {
    phase "Starting services"
    bash "$SCRIPT_DIR/start.sh"
}

# ── Run ──────────────────────────────────────────────────────────────────────

echo -e "${BLUE}InvestPal ecosystem setup${NC}"
[ "$YES" = "1" ] && note "Non-interactive: taking every default."

check_prereqs
clone_repos
install_deps
configure
optional_integrations
prepare_data
start_stack

echo ""
echo -e "${GREEN}Ready.${NC} Run 'make claude' to launch the cockpit."
echo "Anything looking wrong later: 'make doctor'."
