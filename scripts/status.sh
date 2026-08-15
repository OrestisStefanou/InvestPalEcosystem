#!/usr/bin/env bash
# What is running right now. The runtime slice of `make doctor`, in the same
# table `make start` prints — literally the same function, so the two cannot
# drift the way a hand-copied second table did.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

load_env

echo ""
service_table
echo ""
echo "  running = ours and listening, starting = ours but not listening yet,"
echo "  foreign = port held by an untracked process, stopped = not running."
echo ""
echo "  'make doctor' for a full diagnosis, 'make logs' to tail output."
