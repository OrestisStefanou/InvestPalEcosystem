# InvestPalEcosystem

InvestPal is an AI-powered investment advisor. You can ask it about stocks, ETFs, and crypto, get personalized advice, set reminders, and — optionally — connect your brokerage accounts to view your portfolio or place trades. It works as a pure conversational tool without any brokerage credentials.

This is the entry-point repository for the InvestPal app. The app is composed of backend services and optional UI clients:

**Backend (infrastructure)**

| Service | Repository | Port |
|---|---|---|
| InvestPal (REST API + MCP App) | [OrestisStefanou/InvestPal](https://github.com/OrestisStefanou/InvestPal) | 8000 / 9000 |
| Market Data MCP Server | [OrestisStefanou/MarketDataMcpServer](https://github.com/OrestisStefanou/MarketDataMcpServer) | 8080 |
| Alpaca MCP Server | [OrestisStefanou/AlpacaMcpServer](https://github.com/OrestisStefanou/AlpacaMcpServer) | 9091 |
| Coinbase MCP Server | [OrestisStefanou/CoinbaseMcpServer](https://github.com/OrestisStefanou/CoinbaseMcpServer) | 9090 |

**UI clients (optional)**

| Service | Repository | Port |
|---|---|---|
| Telegram Bot | [OrestisStefanou/InvestPalTelegramBot](https://github.com/OrestisStefanou/InvestPalTelegramBot) | 8443 |

---

## Features & Capabilities

| Capability | Details |
|---|---|
| AI Investment Advisor | Powered by OpenAI, Google Gemini, or Anthropic Claude |
| Real-time Market Data | Stocks, ETFs, crypto prices, economic indicators, commodities, market news |
| Personalized Advice | Adapts to your risk tolerance, investment horizon, and goals |
| Cross-session Memory | Recalls notes and context from previous conversations |
| Reminders | Agent can create and track action items for you |
| Alpaca Integration *(optional)* | Read your stock/ETF portfolio and place orders |
| Coinbase Integration *(optional)* | Read your crypto portfolio and place orders |

> **You do not need Alpaca or Coinbase accounts.** InvestPal is fully functional as a conversational investment research tool using only real-time market data.

---

## Ways to Use InvestPal

Once the backend services are running you can interact with InvestPal through several front-ends:

| Interface | Description | Guide |
|---|---|---|
| **Telegram Bot** | Chat with the advisor via the Telegram app | [docs/telegram-bot.md](docs/telegram-bot.md) |
| **Claude Desktop** | Add InvestPal as MCP tools inside Claude Desktop | [docs/claude-desktop.md](docs/claude-desktop.md) |
| **Streamlit Dev UI** | Simple browser-based chat UI, great for local testing | [docs/dev-ui.md](docs/dev-ui.md) |
| **Custom UI** | Build your own client using the InvestPal REST API | [docs/custom-ui.md](docs/custom-ui.md) |

---

## Prerequisites

- **Go** 1.25+
- **Python** 3.13+
- **[uv](https://docs.astral.sh/uv/)** (Python package manager)
- **MongoDB** running locally or a remote URI
- **make**
- **nc** (netcat, used by the start script for health checks — pre-installed on macOS/Linux)

For the Telegram bot only:
- **[ngrok](https://ngrok.com/)** (or another tunneling tool) for local development — the bot uses webhooks, which require a publicly reachable HTTPS URL

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
├── CoinbaseMcpServer/
└── InvestPalTelegramBot/
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

#### `InvestPalTelegramBot/.env`

The bot uses Telegram's webhook mechanism — Telegram pushes updates to a public HTTPS URL that you provide.

**For local development**, use [ngrok](https://ngrok.com/) to expose the local webhook port:

```bash
# Install ngrok, then:
ngrok http 8443
# Copy the https://... URL it gives you — that becomes TELEGRAM_WEBHOOK_URL
```

```env
# From BotFather (https://t.me/BotFather → /newbot)
TELEGRAM_BOT_TOKEN=your_bot_token_here

# Public HTTPS URL that Telegram will push updates to
# Local dev:   use an ngrok URL, e.g. https://xxxx.ngrok-free.app
# Production:  use your server's domain, e.g. https://myserver.example.com
TELEGRAM_WEBHOOK_URL=https://your-ngrok-or-domain-url-here

# Port the bot's webhook server listens on locally
TELEGRAM_WEBHOOK_PORT=8443

# Your Telegram user ID — the bot will only respond to this user
# Find it by messaging @userinfobot on Telegram
TELEGRAM_USER_ID=your_telegram_user_id

# URL of the InvestPal REST API
INVESTPAL_BACKEND_URL=http://127.0.0.1:8000

# Optional: map the Telegram user to an existing InvestPal user ID.
# If omitted, the Telegram user ID is used to create/look up the user.
INVESTPAL_USER_ID=your_investpal_user_id

# Optional: Alpaca credentials forwarded to the InvestPal agent
ALPACA_API_KEY=your_alpaca_key
ALPACA_API_SECRET=your_alpaca_secret

# Optional: Coinbase credentials forwarded to the InvestPal agent
COINBASE_API_KEY=your_coinbase_key_name
COINBASE_API_SECRET=your_coinbase_key_secret
```

### 3. Install dependencies

```bash
make install
```

### 4. Start services

**Backend only (infrastructure):**

```bash
make start
```

This starts all backend services in the background. Logs are written to `logs/<service>.log`.

**Backend + Telegram bot:**

```bash
make start-all
```

This starts the backend first (waiting for MarketDataMcpServer to be ready), then starts the Telegram bot.

> **Note:** Make sure ngrok is already running and `TELEGRAM_WEBHOOK_URL` in `InvestPalTelegramBot/.env` points to your current ngrok URL before running `make start-all`.

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
| InvestPalTelegramBot | 8443 | Telegram bot UI — webhook server (requires ngrok for local dev) |

**Startup order:** MarketDataMcpServer starts first (required by InvestPal), followed by Alpaca and Coinbase servers, then the InvestPal REST API and MCP App. MongoDB must be running before InvestPal starts. The Telegram bot starts last, after the full backend is up.
