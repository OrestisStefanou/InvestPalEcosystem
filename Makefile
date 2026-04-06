REPOS := \
	https://github.com/OrestisStefanou/InvestPal \
	https://github.com/OrestisStefanou/MarketDataMcpServer \
	https://github.com/OrestisStefanou/AlpacaMcpServer \
	https://github.com/OrestisStefanou/CoinbaseMcpServer

.PHONY: clone pull install start stop logs help

help:
	@echo "InvestPal Ecosystem"
	@echo ""
	@echo "Usage:"
	@echo "  make clone    Clone all service repositories"
	@echo "  make install  Install dependencies for all services"
	@echo "  make start    Start all services"
	@echo "  make stop     Stop all running services"
	@echo "  make pull     Pull latest changes in all repositories"
	@echo "  make logs     Tail logs from all services"

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
	@echo "Done."

start:
	@bash scripts/start.sh

stop:
	@bash scripts/stop.sh

logs:
	@tail -f logs/*.log
