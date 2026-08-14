# InvestPalEcosystem

InvestPal is an AI-powered investment advisor. You can ask it about stocks, ETFs, and crypto, get personalized advice, set reminders, and — optionally — connect your brokerage accounts to view your portfolio or place trades. It works as a pure conversational tool without any brokerage credentials.

This is the entry-point repository for the InvestPal app. The app is composed of these backend services:

| Service | Repository | Port |
|---|---|---|
| InvestPal (REST API + MCP App) | [OrestisStefanou/InvestPal](https://github.com/OrestisStefanou/InvestPal) | 8000 / 9000 |
| Market Data MCP Server | [OrestisStefanou/MarketDataMcpServer](https://github.com/OrestisStefanou/MarketDataMcpServer) | 8082 |
| Alpaca MCP Server | [OrestisStefanou/AlpacaMcpServer](https://github.com/OrestisStefanou/AlpacaMcpServer) | 9091 |
| Coinbase MCP Server | [OrestisStefanou/CoinbaseMcpServer](https://github.com/OrestisStefanou/CoinbaseMcpServer) | 9090 |

UI clients are separate; see [Ways to Use InvestPal](#ways-to-use-investpal).

---

## Features & Capabilities

| Capability | Details |
|---|---|
| AI Investment Advisor | Powered by OpenAI, Google Gemini, or Anthropic Claude |
| Real-time Market Data | Stocks, ETFs, crypto prices, economic indicators, commodities, market news |
| Personalized Advice | Adapts to your risk tolerance, investment horizon, and goals |
| Cross-session Memory | Recalls notes from previous conversations, searchable by meaning — embeddings are computed locally, so note text never leaves the machine |
| Reminders | Agent can create and track action items for you |
| Scheduled Workflows | Cron-scheduled tasks the advisor runs on a recurring basis (e.g. weekly portfolio reviews) |
| Alpaca Integration *(optional)* | Read your stock/ETF portfolio and place orders |
| Coinbase Integration *(optional)* | Read your crypto portfolio and place orders |

> **You do not need Alpaca or Coinbase accounts.** InvestPal is fully functional as a conversational investment research tool using only real-time market data.

---

## Ways to Use InvestPal

Once the backend services are running you can interact with InvestPal through several front-ends:

| Interface | Description | Guide |
|---|---|---|
| **Claude Code Cockpit** | Turn Claude Code into the advisor itself; auto-loads the persona and runs your due scheduled workflows | [docs/claude-code-cockpit.md](docs/claude-code-cockpit.md) |
| **Claude Desktop** | Add InvestPal as MCP tools inside Claude Desktop | [docs/claude-desktop.md](docs/claude-desktop.md) |
| **Streamlit Dev UI** | Simple browser-based chat UI, great for local testing | [docs/dev-ui.md](docs/dev-ui.md) |
| **Custom UI** | Build your own client using the InvestPal REST API | [docs/custom-ui.md](docs/custom-ui.md) |

---

## Deployment

| Platform | Guide |
|---|---|
| **Railway** | [docs/deploy-railway.md](docs/deploy-railway.md) |

---

## Prerequisites

- **Go** 1.25+
- **Python** 3.13+
- **[uv](https://docs.astral.sh/uv/)** (Python package manager)
- **make**
- **nc** (netcat, used by the start script for health checks — pre-installed on macOS/Linux)

---

## Setup

### 1. Clone all repositories

Run this from inside the `InvestPalEcosystem/` directory (this repo):

```bash
make clone
```

This clones all service repos inside this repo:

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

Every setting has a working default; the data sources are keyless.

```env
PORT=8082

# Optional. Raises CoinGecko's rate limits; the server works without it.
COIN_GECKO_API_KEY=

# The SEC asks automated clients to identify themselves with a contact address.
# EDGAR rejects a User-Agent containing a URL.
SEC_EDGAR_USER_AGENT=MarketDataMcpServer/1.0 (you@example.com)

# Optional cache TTLs (seconds)
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

InvestPal is a **single-user** application and stores everything in a local turso/SQLite file. There is no MongoDB and no `user_id` anywhere in its API.

> `Settings` uses `extra="forbid"`, so a leftover key in this file (e.g. `MONGO_URI` from an older version) blocks startup.

```env
# LLM provider (openai | google | anthropic)
LLM_PROVIDER=anthropic
LLM_MODEL=claude-sonnet-4-6
ANTHROPIC_API_KEY=your_key_here
# OPENAI_API_KEY=your_key_here
# GOOGLE_API_KEY=your_key_here

# MCP server URLs
MARKET_DATA_MCP_SERVER_URL=http://localhost:8082
ALPACA_MCP_SERVER_URL=http://localhost:9091
COINBASE_MCP_SERVER_URL=http://localhost:9090

# Database. The REST API and the MCP app share this file and must agree on the path.
TURSO_DB_PATH=investpal.db

# Optional
MCP_APP_SERVER_PORT=9000
TEMPERATURE=0.1
CONVERSATION_MESSAGES_LIMIT=15
INVESTMENT_MANAGER_LLM_PROVIDER=anthropic
INVESTMENT_MANAGER_LLM_MODEL=claude-sonnet-4-6
USER_CONTEXT_MEMORY_MANAGER_LLM_PROVIDER=anthropic
USER_CONTEXT_MEMORY_MANAGER_LLM_MODEL=claude-haiku-4-5
WORKFLOW_EXECUTION_AGENT_LLM_PROVIDER=anthropic
WORKFLOW_EXECUTION_AGENT_LLM_MODEL=claude-sonnet-4-6

# Optional: local semantic search over conversation notes (~67MB model, downloaded once).
# Set EMBEDDING_ENABLED=false to skip it — notes still write and list, but search returns nothing.
EMBEDDING_ENABLED=true
EMBEDDING_MODEL_NAME=BAAI/bge-small-en-v1.5
EMBEDDING_CACHE_DIR=~/.cache/investpal/fastembed

# Optional: sync the local database to Turso Cloud. Leave TURSO_SYNC_URL unset to stay
# fully local. Once set, both servers refuse to start until the local database has been
# initialised with `make turso_first_push` or `make turso_first_pull`.
# TURSO_SYNC_URL=
# TURSO_SYNC_AUTH_TOKEN=
# TURSO_SYNC_CLIENT_NAME=investpal-<this-device>   # must differ per device
```

After the first embedding-model download, set `HF_HUB_OFFLINE=1` in your shell — otherwise huggingface_hub makes a metadata call on every model load, which stalls startup when the machine is offline.

### 3. Install dependencies

```bash
make install
```

### 4. Start services

```bash
make start
```

This starts all backend services in the background. Logs are written to `logs/<service>.log`.

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
| MarketDataMcpServer | 8082 | Market data (stocks, crypto, economics, commodities, news) from keyless sources |
| AlpacaMcpServer | 9091 | Alpaca brokerage integration at `http://localhost:9091/mcp` |
| CoinbaseMcpServer | 9090 | Coinbase integration at `http://localhost:9090/mcp` |

**Startup order:** MarketDataMcpServer starts first (required by InvestPal), followed by Alpaca and Coinbase servers, then the InvestPal REST API and MCP App. `make start` health-gates MarketDataMcpServer and the InvestPal MCP App, so it does not return until both are listening.

**Database:** InvestPal keeps everything in a local turso/SQLite file at `TURSO_DB_PATH`, created on first start. No database server is required.

### Turso Cloud sync

Optional, and entirely manual: nothing syncs on startup, on shutdown, or on a timer. Run `make turso_status` first, which prints the state of this machine and names the command that applies, without touching the network.

```
make turso_status      # local vs cloud state and what to run next (read-only, no network)
make turso_first_pull  # create the local database by downloading the cloud one
make turso_first_push  # seed an empty cloud database from this machine's local one
make turso_pull        # apply cloud changes locally
make turso_push        # send local changes up
make turso_verify      # compare local and cloud row counts (read-only)
```

`turso_pull`, `turso_first_pull` and `turso_first_push` rewrite the database underneath any open connection, so these targets refuse to run while the InvestPal REST API or MCP app is up. Run `make stop` first. `turso_push`, `turso_status` and `turso_verify` are safe with the services running.

Because the sync brings the `user_conversation_note_embeddings` rows down with everything else, a synced machine does not need `make backfill_embeddings`. That target (in `InvestPal/`) is only for re-embedding after `EMBEDDING_MODEL_NAME` changes.

Full runbook, including the four file states and the conflict model: `InvestPal/docs/turso_sync.md`.
