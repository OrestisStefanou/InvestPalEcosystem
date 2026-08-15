#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

# Needed for the port sweep at the end, which reads the configured ports.
load_env

if [ ! -d "$LOG_DIR" ] || [ -z "$(ls "$LOG_DIR"/*.pid 2>/dev/null)" ]; then
    echo "No tracked services found."
    # Not the same as "nothing is running": PID files can be gone while the
    # processes are not, which is the state this used to exit on silently.
    report_foreign_ports
    exit 0
fi

echo "Stopping services..."

for pid_file in "$LOG_DIR"/*.pid; do
    name="$(basename "$pid_file" .pid)"
    pid="$(cat "$pid_file")"

    if kill -0 "$pid" 2>/dev/null; then
        echo -e "  Stopping ${GREEN}$name${NC} (PID $pid)..."
        if kill_tree "$pid"; then
            rm -f "$pid_file"
        else
            # Keeping the PID file is deliberate: deleting it here is what turns
            # a survivor into an untracked process that no later stop can reach.
            echo -e "  ${RED}Warning:${NC} $name (PID $pid) survived SIGKILL. Keeping $pid_file."
        fi
    else
        echo -e "  ${YELLOW}$name${NC} was not running (stale PID $pid) — it exited on its own;"
        echo "    logs/$name.log has the reason if you did not expect that."
        rm -f "$pid_file"
    fi
done

report_foreign_ports

echo "Done."
