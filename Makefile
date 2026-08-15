REPOS := \
	https://github.com/OrestisStefanou/InvestPal \
	https://github.com/OrestisStefanou/MarketDataMcpServer \
	https://github.com/OrestisStefanou/AlpacaMcpServer \
	https://github.com/OrestisStefanou/CoinbaseMcpServer \
	https://github.com/OrestisStefanou/InteractiveBrokersMcpServer

.PHONY: setup doctor status claude clone pull install start stop logs help \
	turso_status turso_first_push turso_first_pull turso_push turso_pull turso_verify

help:
	@echo "InvestPal Ecosystem"
	@echo ""
	@echo "First time here:"
	@echo "  make setup      Everything: prerequisites, clone, install, configure, start"
	@echo "                  YES=1 to take every default, FORCE=1 to reconfigure"
	@echo "  make claude     Launch the Claude Code cockpit with credentials loaded"
	@echo ""
	@echo "Day to day:"
	@echo "  make start      Start all backend services"
	@echo "  make stop       Stop all running services"
	@echo "  make status     Show which services are up"
	@echo "  make doctor     Diagnose a broken or drifted install"
	@echo "  make logs       Tail logs from all services"
	@echo "  make pull       Pull latest changes in all repositories"
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

# Launch Claude Code with the root config loaded. .mcp.json interpolates
# ${ALPACA_API_KEY} and friends from the environment, which a file on disk does
# not populate on its own — this is what closes that gap.
claude:
	@if [ ! -f "$(CURDIR)/.env" ]; then \
		echo "No .env found. Run 'make setup' first."; exit 1; \
	fi
	@if ! command -v claude >/dev/null 2>&1; then \
		echo "The 'claude' CLI is not on PATH. See https://claude.com/claude-code"; exit 1; \
	fi
	@set -a; . "$(CURDIR)/.env"; \
		[ -f "$(CURDIR)/.env.secrets" ] && . "$(CURDIR)/.env.secrets"; \
		set +a; exec claude

start:
	@bash scripts/start.sh

stop:
	@bash scripts/stop.sh

logs:
	@tail -f logs/*.log

# ── Turso Cloud sync ─────────────────────────────────────────────────────────
# InvestPal owns the implementation (scripts/turso_sync.py); these targets only
# run it from the right directory so you never have to cd into a nested repo.
#
# Nothing is automatic: there is no sync on startup, shutdown, or timer. The
# database changes only when one of these runs. Run `make turso_status` first if
# you are unsure which command applies — it names the right one for the state
# this machine is in, without touching the network.

# pull / first_push / first_pull rewrite WAL frames underneath whatever
# connections are open, so they must not run while InvestPal holds the file.
# push, status and verify are safe with the services up.
define require_investpal_stopped
	@for name in investpal-api investpal-mcp; do \
		pid_file="$(CURDIR)/logs/$$name.pid"; \
		if [ -f "$$pid_file" ] && kill -0 "$$(cat $$pid_file)" 2>/dev/null; then \
			echo "Error: $$name is still running (PID $$(cat $$pid_file))."; \
			echo "       '$@' rewrites the database underneath its open connections."; \
			echo "       Run 'make stop' first, then '$@' again."; \
			exit 1; \
		fi; \
	done
endef

turso_status:
	@cd $(CURDIR)/InvestPal && $(MAKE) turso_status

turso_verify:
	@cd $(CURDIR)/InvestPal && $(MAKE) turso_verify

turso_push:
	@cd $(CURDIR)/InvestPal && $(MAKE) turso_push

turso_pull:
	$(call require_investpal_stopped)
	@cd $(CURDIR)/InvestPal && $(MAKE) turso_pull

turso_first_push:
	$(call require_investpal_stopped)
	@cd $(CURDIR)/InvestPal && $(MAKE) turso_first_push

turso_first_pull:
	$(call require_investpal_stopped)
	@cd $(CURDIR)/InvestPal && $(MAKE) turso_first_pull
