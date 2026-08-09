# Deploying InvestPal on Railway

This guide walks through deploying the full InvestPal stack — including the Telegram bot — on [Railway](https://railway.app). Each service is deployed as a separate Railway service within a single project and communicates over Railway's private network.

> **⚠️ This guide is out of date and has not been re-validated since InvestPal's single-user
> migration.** It still describes a MongoDB-backed deployment. The current backend stores
> everything in a local turso/SQLite file at `TURSO_DB_PATH`, so `MONGO_URI` / `MONGO_DB_NAME` no
> longer exist and the MongoDB plugin step is obsolete. A container filesystem is ephemeral, so a
> real deployment needs either a Railway volume mounted at the database path or Turso Cloud sync
> (`TURSO_SYNC_URL`, see `InvestPal/docs/turso_sync.md`) — that choice has not been made yet.
> `ALPHA_VANTAGE_API_KEY` is also gone: the market-data server now uses keyless sources and its
> port is configurable via `PORT` (8082 locally). The Telegram bot additionally targets the
> pre-migration REST shape. Treat everything below as a starting point, not a working runbook.

---

## Architecture

```
Railway Project: InvestPal
├── MongoDB              (Railway plugin)
├── market-data-mcp-server   (Go — port 8080)
├── alpaca-mcp-server        (Python — port 9091) [optional]
├── coinbase-mcp-server      (Python — port 9090) [optional]
├── investpal                (Python/FastAPI)
└── investpal-telegram-bot   (Python — port 8443)
```

All services communicate via Railway's private network at `http://<service-name>.railway.internal:<port>`. Only `investpal-telegram-bot` requires a public domain — Telegram needs a reachable HTTPS URL to push webhook events to it.

`investpal` only needs a public domain if you want to expose the REST API to external clients (e.g. a web app or third-party integrations). For personal use where the Telegram bot is the only client, it can remain fully internal.

---

## Prerequisites

**Accounts & access:**
- [Railway account](https://railway.app) (free tier is sufficient to start)
- GitHub account with access to the InvestPal service repositories

**API keys you will need:**
- **Alpha Vantage** key — [alphavantage.co](https://www.alphavantage.co/support/#api-key)
- **CoinGecko** key — [coingecko.com/en/developers/dashboard](https://www.coingecko.com/en/developers/dashboard)
- **LLM provider** key — Anthropic, OpenAI, or Google
- **Telegram bot token** — from [@BotFather](https://t.me/BotFather) (see [docs/telegram-bot.md](telegram-bot.md) Steps 1–2)
- **Your Telegram user ID** — from [@userinfobot](https://t.me/userinfobot)
- *(Optional)* Alpaca API key + secret
- *(Optional)* Coinbase API key name + secret

---

## Step 1 — Create the Railway project

1. Log in to [railway.app](https://railway.app) and click **New Project**.
2. Choose **Empty project**.
3. Name it something like `InvestPal`.

All services created in the following steps will live inside this project and can reach each other over the private network.

---

## Step 2 — Add MongoDB

Railway provides a managed MongoDB plugin:

1. Inside your project, click **+ New** → **Database** → **Add MongoDB**.
2. Railway provisions the database and injects connection variables automatically.
3. Note the variable name `MONGO_URL` — you will reference it when configuring InvestPal.

> **Using MongoDB Atlas instead?** Skip this step and supply your Atlas connection string directly as `MONGO_URI` in the InvestPal service environment in Step 6.

---

## Step 3 — Deploy MarketDataMcpServer

> This service provides real-time stock, ETF, and crypto market data. It is **required** — InvestPal will not start without it.

1. Click **+ New** → **GitHub Repo** and select `OrestisStefanou/MarketDataMcpServer`.
2. Railway will detect a Go project via `go.mod`.
3. In **Service Settings → Build**, set the **Build Command**:
   ```
   go build -o market-data-mcp-server ./cmd/mcp_server
   ```
4. In **Service Settings → Deploy**, set the **Start Command**:
   ```
   ./market-data-mcp-server
   ```
5. Name the service exactly **`market-data-mcp-server`** (used by other services to find it on the private network).
6. Add these environment variables under **Variables**:

   | Variable | Value |
   |---|---|
   | `PORT` | `8080` |
   | `ALPHA_VANTAGE_API_KEY` | your Alpha Vantage key |
   | `COIN_GECKO_API_KEY` | your CoinGecko key |
   | `CACHE_TTL` | `3600` *(optional)* |

   > **Note:** The server port is hardcoded to `8080` in the Go source. Setting `PORT=8080` tells Railway to route traffic to that port.

7. Click **Deploy**. Wait until the service shows **Active**.

---

## Step 4 — Deploy AlpacaMcpServer *(optional)*

Skip this step if you do not need Alpaca brokerage integration.

1. Click **+ New** → **GitHub Repo** → `OrestisStefanou/AlpacaMcpServer`.
2. Name the service **`alpaca-mcp-server`**.
3. In **Service Settings → Deploy**, set the **Start Command**:
   ```
   uv run python main.py
   ```
4. Add these environment variables:

   | Variable | Value |
   |---|---|
   | `PORT` | `9091` |
   | `MCP_PORT` | `9091` |
   | `READ_ONLY` | `False` *(set `True` to disable order placement)* |

   > Alpaca credentials are **not** stored server-side. They are forwarded per-request by the Telegram bot (or any other client) via HTTP headers.

5. Deploy and wait for **Active**.

---

## Step 5 — Deploy CoinbaseMcpServer *(optional)*

Skip this step if you do not need Coinbase integration.

1. Click **+ New** → **GitHub Repo** → `OrestisStefanou/CoinbaseMcpServer`.
2. Name the service **`coinbase-mcp-server`**.
3. In **Service Settings → Deploy**, set the **Start Command**:
   ```
   uv run python main.py
   ```
4. Add these environment variables:

   | Variable | Value |
   |---|---|
   | `PORT` | `9090` |
   | `MCP_PORT` | `9090` |
   | `READ_ONLY` | `false` *(set `true` to disable order placement)* |

5. Deploy and wait for **Active**.

---

## Step 6 — Deploy InvestPal

This is the core service: it exposes the REST API that all UI clients talk to and orchestrates all MCP servers.

1. Click **+ New** → **GitHub Repo** → `OrestisStefanou/InvestPal`.
2. Name the service **`investpal`**.
3. In **Service Settings → Deploy**, set the **Start Command**:
   ```
   uv run fastapi run main.py --host 0.0.0.0 --port $PORT
   ```
4. *(Optional)* Enable a **Public Domain** (Settings → Networking → Generate Domain) if you want the REST API reachable from outside Railway — for example, to connect a web app or use the interactive docs. For personal use with the Telegram bot only, skip this; the Telegram bot reaches InvestPal over the private network.
5. Add the following environment variables. Use Railway's **reference variable** syntax (`${{ServiceName.VARIABLE}}`) for values that come from other services:

   **MongoDB**

   | Variable | Value |
   |---|---|
   | `MONGO_URI` | `${{MongoDB.MONGO_URL}}` |
   | `MONGO_DB_NAME` | `investpal` |

   **LLM provider** — choose one:

   | Variable | Value |
   |---|---|
   | `LLM_PROVIDER` | `anthropic` *(or `openai` or `google`)* |
   | `LLM_MODEL` | `claude-sonnet-4-6` *(adjust to match provider)* |
   | `ANTHROPIC_API_KEY` | your Anthropic key |
   | `OPENAI_API_KEY` | your OpenAI key *(if using OpenAI)* |
   | `GOOGLE_API_KEY` | your Google key *(if using Google)* |

   **MCP server URLs** (private network):

   | Variable | Value |
   |---|---|
   | `MARKET_DATA_MCP_SERVER_URL` | `http://market-data-mcp-server.railway.internal:8080` |
   | `ALPACA_MCP_SERVER_URL` | `http://alpaca-mcp-server.railway.internal:9091` *(omit if not deployed)* |
   | `COINBASE_MCP_SERVER_URL` | `http://coinbase-mcp-server.railway.internal:9090` *(omit if not deployed)* |

   **Optional tuning:**

   | Variable | Value |
   |---|---|
   | `TEMPERATURE` | `0.1` |
   | `CONVERSATION_MESSAGES_LIMIT` | `15` |
   | `INVESTMENT_MANAGER_LLM_PROVIDER` | `anthropic` |
   | `INVESTMENT_MANAGER_LLM_MODEL` | `claude-sonnet-4-6` |
   | `USER_CONTEXT_MEMORY_MANAGER_LLM_PROVIDER` | `anthropic` |
   | `USER_CONTEXT_MEMORY_MANAGER_LLM_MODEL` | `claude-haiku-4-5` |

6. Deploy and wait for **Active**. Verify by opening `https://<your-investpal-domain>.up.railway.app/docs` — you should see the FastAPI interactive docs.

---

## Step 7 — Deploy InvestPalTelegramBot

The Telegram bot uses webhooks: Telegram pushes incoming messages to a public HTTPS URL on the bot service. Railway provides this URL automatically.

Because the webhook URL is only known after the service is first deployed, this step is a two-pass process.

### Pass 1 — Deploy to get the public URL

1. Click **+ New** → **GitHub Repo** → `OrestisStefanou/InvestPalTelegramBot`.
2. Name the service **`investpal-telegram-bot`**.
3. In **Service Settings → Deploy**, set the **Start Command**:
   ```
   uv run python main.py
   ```
4. Enable a **Public Domain** (Settings → Networking → Generate Domain). Copy the URL — it looks like `https://investpal-telegram-bot.up.railway.app`.
5. Add these environment variables:

   | Variable | Value |
   |---|---|
   | `PORT` | `8443` |
   | `TELEGRAM_BOT_TOKEN` | your bot token from BotFather |
   | `TELEGRAM_WEBHOOK_PORT` | `8443` |
   | `TELEGRAM_WEBHOOK_URL` | `https://investpal-telegram-bot.up.railway.app` *(your domain from step 4)* |
   | `TELEGRAM_USER_ID` | your Telegram user ID |
   | `INVESTPAL_BACKEND_URL` | `http://investpal.railway.internal:${{investpal.PORT}}` |
   | `INVESTPAL_USER_ID` | *(optional)* existing InvestPal user ID to map to |

   **With brokerage access** *(optional — add if you want the bot to access your accounts)*:

   | Variable | Value |
   |---|---|
   | `ALPACA_API_KEY` | your Alpaca key |
   | `ALPACA_API_SECRET` | your Alpaca secret |
   | `COINBASE_API_KEY` | your Coinbase key name |
   | `COINBASE_API_SECRET` | your Coinbase key secret |

6. Click **Deploy**.

### Pass 2 — Set the webhook URL and redeploy

If the `TELEGRAM_WEBHOOK_URL` was already set correctly in Pass 1 (you knew the domain before deploying), no second pass is needed. Otherwise, if the service deployed before you could set the URL:

1. Update `TELEGRAM_WEBHOOK_URL` to match the Railway domain you copied in step 4.
2. In the service, click **Redeploy** to apply the change.

The bot registers its webhook with Telegram on startup. Once the redeploy completes and shows **Active**, open Telegram and send `/start` to your bot.

---

## Environment variable reference

Complete listing of all variables by service.

### MarketDataMcpServer

| Variable | Required | Default | Description |
|---|---|---|---|
| `PORT` | yes | — | Must be `8080` (port is hardcoded in the Go binary) |
| `ALPHA_VANTAGE_API_KEY` | yes | — | Alpha Vantage API key |
| `COIN_GECKO_API_KEY` | yes | — | CoinGecko API key |
| `CACHE_TTL` | no | `3600` | Default cache TTL in seconds |
| `ALPHA_VANTAGE_CACHE_TTL` | no | `CACHE_TTL` | Override TTL for Alpha Vantage responses |
| `COIN_GECKO_CACHE_TTL` | no | `CACHE_TTL` | Override TTL for CoinGecko responses |

### AlpacaMcpServer

| Variable | Required | Default | Description |
|---|---|---|---|
| `PORT` | yes | — | Set to `9091` to match `MCP_PORT` |
| `MCP_PORT` | yes | `9091` | Port the FastMCP server listens on |
| `READ_ONLY` | no | `False` | Set `True` to disable order placement |

### CoinbaseMcpServer

| Variable | Required | Default | Description |
|---|---|---|---|
| `PORT` | yes | — | Set to `9090` to match `MCP_PORT` |
| `MCP_PORT` | yes | `9090` | Port the FastMCP server listens on |
| `READ_ONLY` | no | `false` | Set `true` to disable order placement |

### InvestPal

| Variable | Required | Default | Description |
|---|---|---|---|
| `MONGO_URI` | yes | — | MongoDB connection string |
| `MONGO_DB_NAME` | yes | — | Database name, e.g. `investpal` |
| `LLM_PROVIDER` | yes | — | `anthropic`, `openai`, or `google` |
| `LLM_MODEL` | yes | — | Model ID, e.g. `claude-sonnet-4-6` |
| `ANTHROPIC_API_KEY` | if using Anthropic | — | |
| `OPENAI_API_KEY` | if using OpenAI | — | |
| `GOOGLE_API_KEY` | if using Google | — | |
| `MARKET_DATA_MCP_SERVER_URL` | yes | — | Internal URL of MarketDataMcpServer |
| `ALPACA_MCP_SERVER_URL` | no | — | Internal URL of AlpacaMcpServer |
| `COINBASE_MCP_SERVER_URL` | no | — | Internal URL of CoinbaseMcpServer |
| `TEMPERATURE` | no | `0.1` | LLM temperature |
| `CONVERSATION_MESSAGES_LIMIT` | no | `15` | Max messages kept in context |
| `INVESTMENT_MANAGER_LLM_PROVIDER` | no | `anthropic` | Provider for the investment manager agent |
| `INVESTMENT_MANAGER_LLM_MODEL` | no | `claude-sonnet-4-6` | Model for the investment manager agent |
| `USER_CONTEXT_MEMORY_MANAGER_LLM_PROVIDER` | no | `anthropic` | Provider for the memory manager agent |
| `USER_CONTEXT_MEMORY_MANAGER_LLM_MODEL` | no | `claude-haiku-4-5` | Model for the memory manager agent |

### InvestPalTelegramBot

| Variable | Required | Default | Description |
|---|---|---|---|
| `PORT` | yes | — | Must match `TELEGRAM_WEBHOOK_PORT` (set to `8443`) |
| `TELEGRAM_BOT_TOKEN` | yes | — | Token from BotFather |
| `TELEGRAM_WEBHOOK_URL` | yes | — | Public HTTPS Railway domain of this service |
| `TELEGRAM_WEBHOOK_PORT` | yes | — | Port the bot listens on — set to `8443` |
| `TELEGRAM_USER_ID` | yes | — | Telegram user ID allowed to use the bot |
| `INVESTPAL_BACKEND_URL` | yes | — | Internal URL of the InvestPal service |
| `INVESTPAL_USER_ID` | no | — | Map Telegram user to existing InvestPal user ID |
| `INVESTPAL_BACKEND_TIMEOUT_MINUTES` | no | `5` | Timeout for InvestPal API requests |
| `ALPACA_API_KEY` | no | — | Forwarded to InvestPal for brokerage access |
| `ALPACA_API_SECRET` | no | — | Forwarded to InvestPal for brokerage access |
| `COINBASE_API_KEY` | no | — | Forwarded to InvestPal for brokerage access |
| `COINBASE_API_SECRET` | no | — | Forwarded to InvestPal for brokerage access |

---

## Verifying the deployment

**1. Check each service is healthy**

In the Railway project view, all services should show a green **Active** status. Open the **Logs** tab for any service that is not active to diagnose the failure.

**2. Check the InvestPal REST API** *(only if you enabled a public domain)*

```bash
curl https://<your-investpal-domain>.up.railway.app/docs
```

This should return the FastAPI Swagger UI HTML. You can also browse to it in a browser. Skip this check if InvestPal is internal-only.

**3. Check the Telegram bot**

Open Telegram, find your bot by the username you set in BotFather, and send `/start`. The bot should respond with a welcome message.

**Common issues:**

| Symptom | Likely cause |
|---|---|
| InvestPal service crashes on startup | `MONGO_URI` incorrect or MongoDB service not yet ready |
| InvestPal service starts but AI calls fail | MCP server URL wrong — check `MARKET_DATA_MCP_SERVER_URL` uses the correct private hostname and port |
| Telegram bot starts but receives no messages | `TELEGRAM_WEBHOOK_URL` is wrong or not updated after deploy — redeploy after fixing the value |
| Telegram bot responds with "Unauthorized" | `TELEGRAM_USER_ID` does not match your actual Telegram user ID |
| AlpacaMcpServer / CoinbaseMcpServer crashes | `MCP_PORT` does not match `PORT` — both should be set to the same value (`9091` / `9090`) |

---

## Notes

- **Ephemeral cache**: MarketDataMcpServer uses an in-memory Badger cache. The cache is cleared on every restart or redeploy — this is expected. Data is always re-fetched from Alpha Vantage and CoinGecko on cache miss.
- **Brokerage services are optional**: If you skip Steps 4 and 5, omit `ALPACA_MCP_SERVER_URL` and `COINBASE_MCP_SERVER_URL` from InvestPal's variables. The advisor works fully in conversational mode using only market data.
- **Private networking scope**: Railway private networking (`*.railway.internal`) only works between services within the same Railway project.
- **MongoDB Atlas alternative**: If you prefer to use MongoDB Atlas instead of the Railway plugin, skip Step 2 and set `MONGO_URI` in the InvestPal service to your Atlas connection string directly.
- **Automatic deploys**: By default Railway redeploys a service whenever its connected GitHub repo receives a new commit to the default branch. You can disable this in **Service Settings → Deploy**.
