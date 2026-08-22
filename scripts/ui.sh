#!/usr/bin/env bash
# The local web UI. Opt-in rather than part of `make start`, because it is the
# one component here that needs Node, and the stack is designed to work without
# it: the Claude Code cockpit is the recommended surface and needs no Node at
# all. Keeping this out of `make start` is also what keeps `make doctor` usable
# as a gate — doctor FAILs on a registered service that is not running, so a
# cockpit-only machine would otherwise go red for something it never wanted.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

mkdir -p "$LOG_DIR"
load_env

WEB_DIR="$REPO_DIR/investpal-web"

case "${1:-start}" in
    stop)
        if pid_alive investpal-web; then
            echo -e "  Stopping ${GREEN}investpal-web${NC} (PID $(service_pid investpal-web))..."
            kill_tree "$(service_pid investpal-web)" && rm -f "$LOG_DIR/investpal-web.pid"
        else
            echo "investpal-web is not running."
            rm -f "$LOG_DIR/investpal-web.pid"
        fi
        exit 0
        ;;
esac

if ! have_node; then
    echo -e "${RED}Error:${NC} node and npm are not on PATH."
    echo "  The web UI is the only part of this stack that needs them; everything"
    echo "  else, including the Claude Code cockpit, works without Node."
    echo "  Install from https://nodejs.org, or with your package manager."
    exit 1
fi

# Lazy and idempotent, which is why `make install` needs no web-app step and the
# `make setup` path never touches npm.
if [ ! -d "$WEB_DIR/node_modules" ]; then
    echo "Installing web UI dependencies (first run only)..."
    if [ -f "$WEB_DIR/package-lock.json" ]; then
        (cd "$WEB_DIR" && npm ci)
    else
        (cd "$WEB_DIR" && npm install)
    fi
fi

# Reported, never fatal. The UI loads perfectly well with the backend down and
# then fails every request, which is a confusing enough state to name up front.
if ! port_open "$INVESTPAL_API_PORT"; then
    echo -e "  ${YELLOW}Warning:${NC} nothing is listening on port $INVESTPAL_API_PORT."
    echo "    Run 'make start' first, or every request from the UI will fail."
fi

collect_env investpal-web
start_service "investpal-web" "$INVESTPAL_WEB_PORT" "$WEB_DIR" "npm run dev" "${ENV_PAIRS[@]}"
# 60 rather than the default 30: the first `npm run dev` after an install pays
# for an esbuild dependency-optimise pass before it binds the port.
wait_for_service "InvestPal Web UI" "investpal-web" "$INVESTPAL_WEB_PORT" 60

echo ""
echo -e "${GREEN}Web UI ready${NC} at http://localhost:$INVESTPAL_WEB_PORT"
echo "  Talking to the REST API on http://localhost:$INVESTPAL_API_PORT"
echo "  'make stop' stops it along with everything else; 'make ui_stop' stops only this."
echo "  Output: logs/investpal-web.log"
