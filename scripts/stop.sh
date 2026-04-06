#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$REPO_DIR/logs"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Kill a process and all its descendants recursively
kill_tree() {
    local pid="$1"
    local children
    children=$(pgrep -P "$pid" 2>/dev/null) || true
    for child in $children; do
        kill_tree "$child"
    done
    kill "$pid" 2>/dev/null || true
}

if [ ! -d "$LOG_DIR" ] || [ -z "$(ls "$LOG_DIR"/*.pid 2>/dev/null)" ]; then
    echo "No running services found."
    exit 0
fi

echo "Stopping services..."

for pid_file in "$LOG_DIR"/*.pid; do
    name="$(basename "$pid_file" .pid)"
    pid="$(cat "$pid_file")"

    if kill -0 "$pid" 2>/dev/null; then
        echo -e "  Stopping ${GREEN}$name${NC} (PID $pid)..."
        kill_tree "$pid"
    else
        echo -e "  ${RED}$name${NC} was not running (stale PID $pid)"
    fi

    rm -f "$pid_file"
done

echo "Done."
