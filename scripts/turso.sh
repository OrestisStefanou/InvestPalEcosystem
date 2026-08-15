#!/usr/bin/env bash
# Run one of InvestPal's turso_* make targets from the ecosystem root, with the
# same environment fan-out the services get at start time.
#
# The fan-out is not optional here. LLM_PROVIDER, LLM_MODEL and
# MARKET_DATA_MCP_SERVER_URL have no defaults in InvestPal/config.py, so
# `cd InvestPal && make turso_status` dies in pydantic before it reads a single
# byte of the database — which meant the exact command the "not a sync database"
# startup error tells you to run could not itself run.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

load_env

# turso_pull / turso_first_push / turso_first_pull rewrite WAL frames underneath
# whatever connections are open, so they must not run while InvestPal holds the
# file. Checking the PID files alone is not enough: an untracked process from an
# earlier run has no PID file and would sail straight past that guard, so the
# ports are checked too — a bound port means something has the database open.
case "$1" in
    turso_pull|turso_first_push|turso_first_pull)
        for entry in "investpal-api:$INVESTPAL_API_PORT" "investpal-mcp:$INVESTPAL_MCP_PORT"; do
            name="${entry%%:*}"
            port="${entry##*:}"
            owner=""
            pid_alive "$name" && owner="$(service_pid "$name")"
            [ -z "$owner" ] && owner="$(port_pid "$port")"
            if [ -n "$owner" ]; then
                echo -e "${RED}Error:${NC} $name is still running (PID $owner, port $port)."
                echo "       '$1' rewrites the database underneath its open connections."
                echo "       Run 'make stop' first, then '$1' again."
                exit 1
            fi
        done
        ;;
esac

while IFS= read -r pair; do
    [ -n "$pair" ] && export "$pair"
done < <(service_env investpal-api)

exec make -C "$REPO_DIR/InvestPal" --no-print-directory "$@"
