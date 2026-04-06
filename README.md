# InvestPalEcosystem

This is the entry-point repository for the InvestPal app. The app is composed of four services:

| Service | Repository | Port |
|---|---|---|
| InvestPal (REST API + MCP App) | [OrestisStefanou/InvestPal](https://github.com/OrestisStefanou/InvestPal) | 8000 / 9000 |
| Market Data MCP Server | [OrestisStefanou/MarketDataMcpServer](https://github.com/OrestisStefanou/MarketDataMcpServer) | 8080 |
| Alpaca MCP Server | [OrestisStefanou/AlpacaMcpServer](https://github.com/OrestisStefanou/AlpacaMcpServer) | 9091 |
| Coinbase MCP Server | [OrestisStefanou/CoinbaseMcpServer](https://github.com/OrestisStefanou/CoinbaseMcpServer) | 9090 |

---

## Prerequisites

- **Go** 1.25+
- **Python** 3.13+
- **[uv](https://docs.astral.sh/uv/)** (Python package manager)
- **MongoDB** running locally or a remote URI
- **make**
- **nc** (netcat, used by the start script for health checks — pre-installed on macOS/Linux)

---

## Setup

### 1. Clone all repositories

Run this from inside the `InvestPalEcosystem/` directory (this repo):

```bash
make clone
```

This clones all four service repos inside this repo:

```
InvestPalEcosystem/   ← this repo
├── Makefile
├── scripts/
├── InvestPal/
├── MarketDataMcpServer/
├── AlpacaMcpServer/
└── CoinbaseMcpServer/
```

### 2. Configure environment variables

Each service reads its configuration from a `.env` file in its own directory. Create these before starting:

#### `MarketDataMcpServer/.env`

```env
ALPHA_VANTAGE_API_KEY=your_key_here
COIN_GECKO_API_KEY=your_key_here
# Optional
CACHE_TTL=3600
```

#### `AlpacaMcpServer/.env`

```env
# For local dev only — in production, credentials are passed per-request via headers
ALPACA_API_KEY=your_key_here
ALPACA_API_SECRET=your_secret_here
# Optional
ALPACA_API_BASE_URL=https://paper-api.alpaca.markets/v2
MCP_PORT=9091
READ_ONLY=False
```

#### `CoinbaseMcpServer/.env`

```env
# For local dev only — in production, credentials are passed per-request via headers
coinbase_key_name=your_key_name
coinbase_key_secret=your_key_secret
# Optional
MCP_PORT=9090
READ_ONLY=false
```

#### `InvestPal/.env`

```env
# MongoDB
MONGO_URI=mongodb://localhost:27017
MONGO_DB_NAME=investpal

# LLM provider (openai | google | anthropic)
LLM_PROVIDER=anthropic
LLM_MODEL=claude-sonnet-4-6
ANTHROPIC_API_KEY=your_key_here
# OPENAI_API_KEY=your_key_here
# GOOGLE_API_KEY=your_key_here

# MCP server URLs
MARKET_DATA_MCP_SERVER_URL=http://localhost:8080
ALPACA_MCP_SERVER_URL=http://localhost:9091
COINBASE_MCP_SERVER_URL=http://localhost:9090

# Optional
MCP_APP_SERVER_PORT=9000
TEMPERATURE=0.1
CONVERSATION_MESSAGES_LIMIT=15
INVESTMENT_MANAGER_LLM_PROVIDER=anthropic
INVESTMENT_MANAGER_LLM_MODEL=claude-sonnet-4-6
USER_CONTEXT_MEMORY_MANAGER_LLM_PROVIDER=anthropic
USER_CONTEXT_MEMORY_MANAGER_LLM_MODEL=claude-haiku-4-5
```

### 3. Install dependencies

```bash
make install
```

### 4. Start all services

```bash
make start
```

This starts all services in the background. Logs are written to `logs/<service>.log`.

To stop all services:

```bash
make stop
```

To pull the latest changes across all repos:

```bash
make pull
```

To tail all logs:

```bash
make logs
```

---

## Service Overview

| Service | Port | Description |
|---|---|---|
| InvestPal REST API | 8000 | Main API — docs at `http://localhost:8000/docs` |
| InvestPal MCP App | 9000 | Internal MCP server at `http://localhost:9000/mcp` |
| MarketDataMcpServer | 8080 | Market data (stocks, crypto) via Alpha Vantage & CoinGecko |
| AlpacaMcpServer | 9091 | Alpaca brokerage integration at `http://localhost:9091/mcp` |
| CoinbaseMcpServer | 9090 | Coinbase integration at `http://localhost:9090/mcp` |

**Startup order:** MarketDataMcpServer starts first (required by InvestPal), followed by Alpaca and Coinbase servers, then the InvestPal REST API and MCP App. MongoDB must be running before InvestPal starts.
