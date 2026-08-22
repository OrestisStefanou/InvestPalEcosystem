REPOS := \
	https://github.com/OrestisStefanou/InvestPal \
	https://github.com/OrestisStefanou/MarketDataMcpServer \
	https://github.com/OrestisStefanou/AlpacaMcpServer \
	https://github.com/OrestisStefanou/CoinbaseMcpServer \
	https://github.com/OrestisStefanou/InteractiveBrokersMcpServer

.PHONY: setup doctor status claude clone pull install start stop logs help ui ui_stop \
	turso_status turso_first_push turso_first_pull turso_push turso_pull turso_verify

help:
	@echo "InvestPal Ecosystem"
	@echo ""
	@echo "First time here:"
	@echo "  make setup      Everything: prerequisites, clone, install, configure, start"
	@echo "                  YES=1 to take every default, FORCE=1 to reconfigure"
	@echo "  make claude     Launch the Claude Code cockpit"
	@echo ""
	@echo "Day to day:"
	@echo "  make start      Start all backend services"
	@echo "  make stop       Stop all running services"
	@echo "  make status     Show which services are up"
	@echo "  make doctor     Diagnose a broken or drifted install"
	@echo "  make logs       Tail logs from all services"
	@echo "  make pull       Pull latest changes in all repositories"
	@echo ""
	@echo "Front-ends:"
	@echo "  make ui         Start the local web UI on http://localhost:5173 (needs Node)"
	@echo "  make ui_stop    Stop just the web UI"
	@echo ""
	@echo "  Configuration lives in .env (and credentials in .env.secrets),"
	@echo "  both at the root of this repo. See .env.example."
	@echo ""
	@echo "Lower level:"
	@echo "  make clone      Clone all service repositories"
	@echo "  make install    Install dependencies for all services"
	@echo ""
	@echo "Turso Cloud sync (optional, needs TURSO_SYNC_URL in .env):"
	@echo "  make turso_status      Local vs cloud state and what to run next (read-only, no network)"
	@echo "  make turso_first_pull  Create the local database by downloading the cloud one"
	@echo "                         FORCE=1 to replace a local one that already has rows"
	@echo "  make turso_first_push  Seed an empty cloud database from this machine's local one"
	@echo "  make turso_pull        Apply cloud changes locally"
	@echo "  make turso_push        Send local changes up"
	@echo "  make turso_verify      Compare local and cloud row counts (read-only)"
	@echo ""
	@echo "  Nothing syncs automatically. See InvestPal/docs/turso_sync.md."

clone:
	@echo "Cloning repositories into $(CURDIR)..."
	@for repo in $(REPOS); do \
		name=$$(basename $$repo); \
		if [ -d "$(CURDIR)/$$name" ]; then \
			echo "  $$name already exists, skipping."; \
		else \
			echo "  Cloning $$name..."; \
			git clone $$repo $(CURDIR)/$$name; \
		fi; \
	done
	@echo "Done. All repositories are in $(CURDIR)/"

pull:
	@echo "Pulling latest changes..."
	@for repo in $(REPOS); do \
		name=$$(basename $$repo); \
		if [ -d "$(CURDIR)/$$name" ]; then \
			echo "  Pulling $$name..."; \
			git -C $(CURDIR)/$$name pull; \
		else \
			echo "  $$name not found, skipping (run 'make clone' first)."; \
		fi; \
	done
	@echo "Done."

install:
	@echo "Installing dependencies..."
	@echo "  MarketDataMcpServer (Go)..."
	@cd $(CURDIR)/MarketDataMcpServer && make install
	@echo "  InvestPal (Python/uv)..."
	@cd $(CURDIR)/InvestPal && uv sync
	@echo "  AlpacaMcpServer (Python/uv)..."
	@cd $(CURDIR)/AlpacaMcpServer && uv sync
	@echo "  CoinbaseMcpServer (Python/uv)..."
	@cd $(CURDIR)/CoinbaseMcpServer && uv sync
	@if [ -d "$(CURDIR)/InteractiveBrokersMcpServer" ]; then \
		echo "  InteractiveBrokersMcpServer (Python/uv)..."; \
		cd $(CURDIR)/InteractiveBrokersMcpServer && uv sync; \
	fi
	@echo "Done."

setup:
	@bash scripts/setup.sh

doctor:
	@bash scripts/doctor.sh

status:
	@bash scripts/status.sh

# Launch Claude Code with .env loaded. .env.secrets is deliberately NOT sourced:
# the broker MCP servers read their credentials from their own process
# environment, so no secret ever needs to exist inside Claude Code's. That used
# not to be true, back when .mcp.json interpolated the keys into request headers.
#
# Bare `claude` now works just as well. This target survives as a guard: it fails
# fast when setup has not been run or the CLI is missing, and it exports .env for
# anything in the session that wants it.
claude:
	@if [ ! -f "$(CURDIR)/.env" ]; then \
		echo "No .env found. Run 'make setup' first."; exit 1; \
	fi
	@if ! command -v claude >/dev/null 2>&1; then \
		echo "The 'claude' CLI is not on PATH. See https://claude.com/claude-code"; exit 1; \
	fi
	@set -a; . "$(CURDIR)/.env"; set +a; exec claude

start:
	@bash scripts/start.sh

stop:
	@bash scripts/stop.sh

# The only target that needs Node, which is why it is not part of `make start`
# and nothing on the `make setup` path touches npm. `make stop` still stops it:
# stop.sh sweeps every PID file rather than a fixed list.
ui:
	@bash scripts/ui.sh start

ui_stop:
	@bash scripts/ui.sh stop

logs:
	@tail -f logs/*.log

# ── Turso Cloud sync ─────────────────────────────────────────────────────────
# InvestPal owns the implementation (scripts/turso_sync.py); these targets only
# run it from the right directory, through scripts/turso.sh so it inherits the
# same root-config fan-out the services get. Calling `make -C InvestPal` here
# directly skipped that and made every one of these targets fail in pydantic.
#
# Nothing is automatic: there is no sync on startup, shutdown, or timer. The
# database changes only when one of these runs. Run `make turso_status` first if
# you are unsure which command applies — it names the right one for the state
# this machine is in, without touching the network.
#
# The "InvestPal must be stopped" guard for the destructive targets lives in
# scripts/turso.sh, where it can check listening ports as well as PID files.
#
# YES=1 skips the confirmations, FORCE=1 lets turso_first_pull replace a local
# database that has rows in it. Both are forwarded explicitly rather than left
# to make's variable export rules, which do not reach across the shell script.

turso_status:
	@bash scripts/turso.sh turso_status

turso_verify:
	@bash scripts/turso.sh turso_verify

turso_push:
	@bash scripts/turso.sh turso_push

turso_pull:
	@YES="$(YES)" bash scripts/turso.sh turso_pull

turso_first_push:
	@YES="$(YES)" bash scripts/turso.sh turso_first_push

turso_first_pull:
	@YES="$(YES)" FORCE="$(FORCE)" bash scripts/turso.sh turso_first_pull
