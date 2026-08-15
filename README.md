# InvestPalEcosystem

InvestPal is an AI-powered investment advisor. You can ask it about stocks, ETFs, and crypto, get personalized advice, set reminders, and — optionally — connect your brokerage accounts to view your portfolio or place trades. It works as a pure conversational tool without any brokerage credentials.

This is the entry-point repository for the InvestPal app. The app is composed of these backend services:

| Service | Repository | Port |
|---|---|---|
| InvestPal (REST API + MCP App) | [OrestisStefanou/InvestPal](https://github.com/OrestisStefanou/InvestPal) | 8000 / 9000 |
| Market Data MCP Server | [OrestisStefanou/MarketDataMcpServer](https://github.com/OrestisStefanou/MarketDataMcpServer) | 8082 |
| Alpaca MCP Server | [OrestisStefanou/AlpacaMcpServer](https://github.com/OrestisStefanou/AlpacaMcpServer) | 9091 |
| Coinbase MCP Server | [OrestisStefanou/CoinbaseMcpServer](https://github.com/OrestisStefanou/CoinbaseMcpServer) | 9090 |
| Interactive Brokers MCP Server | [OrestisStefanou/InteractiveBrokersMcpServer](https://github.com/OrestisStefanou/InteractiveBrokersMcpServer) | 9092 |

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
| Interactive Brokers Integration *(optional)* | Read your IB accounts, positions, balances and trades, and place orders |

> **You do not need Alpaca, Coinbase or Interactive Brokers accounts.** InvestPal is fully functional as a conversational investment research tool using only real-time market data.

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

## Prerequisites

`make setup` checks all of these and tells you what to install.

- **git**, **make**, **curl**, **nc** (pre-installed on macOS and most Linux)
- **Go** 1.25+
- **[uv](https://docs.astral.sh/uv/)** — supplies the Python 3.13 runtimes for the four Python services
- **Java** 1.8+ — only for the Interactive Brokers gateway; skip it if you are not using IB

---

## Setup

```bash
git clone https://github.com/OrestisStefanou/InvestPalEcosystem
cd InvestPalEcosystem
make setup
```

That is the whole thing. `make setup` checks prerequisites, clones the five service
repos, installs their dependencies, writes your configuration, prepares the database
and search index, and starts everything. It asks three optional questions, all of
which you can skip with Enter. Run `make setup YES=1` to skip them for you.

**You do not need an API key.** In the Claude Code cockpit, Claude Code is the LLM.
An LLM key is only for InvestPal's own agent — see [Backend agent](#backend-agent-optional) below.

Re-run `make setup` any time; it only does what is still missing. `make setup FORCE=1`
reconfigures from scratch.

### Configuration

Two files at the root of this repo, both gitignored, both created by `make setup`:

| File | Contents |
|---|---|
| `.env` | Ports, URLs, cache TTLs, feature switches. See [`.env.example`](.env.example) |
| `.env.secrets` | API keys and tokens, mode 600. See [`.env.secrets.example`](.env.secrets.example) |

You never edit a `.env` inside a service repo. At start time `scripts/lib.sh` exports
the right subset of these values into each service's process, which means the settings
survive re-cloning a service repo, and the three name collisions between services
(`MCP_PORT` and `READ_ONLY` are each used by three of them) are resolved in one place.

The split is a trust boundary, not a filing system: the Claude Code agent is denied
read access to `.env.secrets` by the `permissions.deny` rules in
`.claude/settings.json`. Note the limit of that — `make claude` exports these values
into Claude Code's own environment, because `.mcp.json` interpolates them into request
headers and the broker MCP servers accept credentials no other way.

### Variable reference

Everything has a working default. The table lists what you are most likely to change;
the two example files document the rest inline.

| Variable | File | Default | Description |
|---|---|---|---|
| `SEC_EDGAR_USER_AGENT` | `.env` | placeholder | EDGAR returns 403 without a real contact address |
| `MARKET_DATA_PORT` | `.env` | `8082` | The Go server's own default is 8080; the start script gates 8082 |
| `INVESTPAL_MCP_PORT` | `.env` | `9000` | Must agree with `.mcp.json`; `make doctor` cross-checks |
| `ALPACA_READ_ONLY` | `.env` | `false` | `true` hides the order-placing tools from the advisor |
| `COINBASE_READ_ONLY` | `.env` | `false` | As above |
| `IB_READ_ONLY` | `.env` | `false` | As above |
| `ALPACA_API_BASE_URL` | `.env` | paper endpoint | Live trading needs an explicit override |
| `TURSO_SYNC_URL` | `.env` | unset | Optional Turso Cloud sync; see below |
| `EMBEDDING_ENABLED` | `.env` | `true` | `false` disables semantic search over notes |
| `CONNECT_BROKERS_TO_BACKEND` | `.env` | `false` | Give InvestPal's own agent the broker tools too |
| `LLM_PROVIDER` / `LLM_MODEL` | `.env` | `anthropic` / `claude-sonnet-4-6` | Backend agent only. Do not blank them: InvestPal gives them no default and will not start |
| `ANTHROPIC_API_KEY` | `.env.secrets` | unset | Backend agent only |
| `ALPACA_API_KEY` / `ALPACA_API_SECRET` | `.env.secrets` | unset | Optional |
| `COINBASE_API_KEY` / `COINBASE_API_SECRET` | `.env.secrets` | unset | Optional; the secret must be base64-encoded |
| `COIN_GECKO_API_KEY` | `.env.secrets` | unset | Optional; only raises CoinGecko's rate limits |

### Backend agent (optional)

InvestPal ships its own LLM agent, used by the `/chat` REST endpoint, the Streamlit dev
UI, and workflows the backend executes itself. That agent needs a provider API key. The
Claude Code cockpit does not use any of it and needs no key.

To enable it, answer yes when `make setup` asks, or put a key in `.env.secrets` matching
the `LLM_PROVIDER` set in `.env`.

### Interactive Brokers (optional)

IB authenticates through a browser login to its own gateway rather than with API keys:

1. Download the Client Portal API gateway from Interactive Brokers and unpack it into
   `InteractiveBrokersMcpServer/ib_clientportal/`.
2. `make start` launches it and waits for port 5000. Missing Java or a missing gateway
   produces a warning, never a failed startup.
3. Open `https://localhost:5000`, accept the self-signed certificate, and log in. The
   session survives closing the browser but expires; `make start` and `make doctor` both
   report whether it is still authenticated.

---

## Running it

| Command | What it does |
|---|---|
| `make claude` | Launch the Claude Code cockpit with credentials loaded |
| `make start` / `make stop` | Start or stop all backend services |
| `make status` | Which services are up |
| `make doctor` | Full diagnosis of a broken or drifted install |
| `make logs` | Tail every service log |
| `make pull` | Pull the latest changes across all repos |

Launch the cockpit with `make claude` rather than bare `claude`: `.mcp.json` reads your
brokerage keys from the environment, and a file on disk does not populate it on its own.

When anything looks wrong, `make doctor` is the first move. It checks the toolchain,
the repos, config coherence, port agreement with `.mcp.json`, every running service,
the database state, and secret hygiene, and prints a fix for each problem it finds. It
exits non-zero on a real failure, so it also works as a gate in a script.

---

## Service Overview

| Service | Port | Description |
|---|---|---|
| InvestPal REST API | 8000 | Main API — docs at `http://localhost:8000/docs` |
| InvestPal MCP App | 9000 | Internal MCP server at `http://localhost:9000/mcp` |
| MarketDataMcpServer | 8082 | Market data (stocks, crypto, economics, commodities, news) from keyless sources |
| AlpacaMcpServer | 9091 | Alpaca brokerage integration at `http://localhost:9091/mcp` |
| CoinbaseMcpServer | 9090 | Coinbase integration at `http://localhost:9090/mcp` |
| InteractiveBrokersMcpServer | 9092 | Interactive Brokers integration at `http://localhost:9092/mcp` |
| IB Client Portal Gateway | 5000 | Interactive Brokers' own Java gateway at `https://localhost:5000`, started only if installed |

**Startup order:** MarketDataMcpServer starts first (required by InvestPal), followed by the Alpaca, Coinbase and Interactive Brokers servers, then the InvestPal REST API and MCP App. `make start` health-gates MarketDataMcpServer and the InvestPal MCP App, so it does not return until both are listening.

The Interactive Brokers block is skipped entirely when `InteractiveBrokersMcpServer/` is not cloned. When it is, the IB Client Portal Gateway starts before the MCP server and is gated on port 5000 non-fatally: a missing gateway, a missing Java runtime, or a gateway that fails to come up produces a warning rather than aborting startup. Once the gateway is listening, `make start` also reports whether its session is authenticated.

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
