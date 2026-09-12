<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/logo-dark.png">
    <img src="assets/logo-light.png" alt="InvestPal" width="420">
  </picture>
</p>

<p align="center">
  <a href="docs/architecture.md">Architecture</a> &nbsp;·&nbsp;
  <a href="docs/skills.md">Skills</a> &nbsp;·&nbsp;
  <a href="docs/market-data.md">Market data</a> &nbsp;·&nbsp;
  <a href="#setup">Setup</a> &nbsp;·&nbsp;
  <a href="#ways-to-use-investpal">Ways to use it</a> &nbsp;·&nbsp;
  <a href="https://orestisstefanou.github.io/investpal/">Website</a>
</p>

---

InvestPal is an AI-powered investment advisor. You can ask it about stocks, ETFs, and crypto, get personalized advice, set reminders, and — optionally — connect your brokerage accounts to view your portfolio or place trades. It works as a pure conversational tool without any brokerage credentials.

This is the entry-point repository for the InvestPal app. The app is composed of these backend services:

| Service | Repository | Port |
|---|---|---|
| InvestPal (REST API + MCP App) | [OrestisStefanou/InvestPal](https://github.com/OrestisStefanou/InvestPal) | 8000 / 9000 |
| Market Data (OpenBB) | [OpenBB-finance/OpenBB](https://github.com/OpenBB-finance/OpenBB), pinned venv | 8082 / 8083 |
| Alpaca MCP Server | [OrestisStefanou/AlpacaMcpServer](https://github.com/OrestisStefanou/AlpacaMcpServer) | 9091 |
| Coinbase MCP Server | [OrestisStefanou/CoinbaseMcpServer](https://github.com/OrestisStefanou/CoinbaseMcpServer) | 9090 |
| Interactive Brokers MCP Server | [OrestisStefanou/InteractiveBrokersMcpServer](https://github.com/OrestisStefanou/InteractiveBrokersMcpServer) | 9092 |

UI clients are separate; see [Ways to Use InvestPal](#ways-to-use-investpal). For how the pieces
fit together, see [Architecture](docs/architecture.md).

---

## Features & Capabilities

| Capability | Details |
|---|---|
| AI Investment Advisor | Powered by OpenAI, Google Gemini, or Anthropic Claude |
| [Skills](docs/skills.md) | Fifteen written analytical procedures, drawn from Graham and Dodd and Howard Marks, that the advisor follows instead of reasoning ad hoc |
| [Market Data](docs/market-data.md) | Stocks, ETFs, filings, financial statements, economic indicators, commodities and news, through the OpenBB MCP server. Most of it needs no API key |
| Personalized Advice | Adapts to your risk tolerance, investment horizon, and goals |
| Cross-session Memory | Recalls notes from previous conversations, searchable by meaning — embeddings are computed locally, so note text never leaves the machine |
| Reminders | Agent can create and track action items for you |
| Scheduled Workflows | Cron-scheduled tasks the advisor runs on a recurring basis (e.g. weekly portfolio reviews) |
| Alpaca Integration *(optional)* | Read your stock/ETF portfolio and place orders |
| Coinbase Integration *(optional)* | Read your crypto portfolio and place orders |
| Interactive Brokers Integration *(optional)* | Read your IB accounts, positions, balances and trades, and place orders |

> **You do not need Alpaca, Coinbase or Interactive Brokers accounts.** InvestPal is fully functional as a conversational investment research tool using only market data.
>
> One free registration key is worth having: FRED covers commodity prices and most Federal Reserve series, which have no other free provider. `make setup` asks for it. See [Market data](docs/market-data.md).

---

## Ways to Use InvestPal

Once the backend services are running you can interact with InvestPal through several front-ends:

| Interface | Description | Guide |
|---|---|---|
| **Claude Code Cockpit** | Turn Claude Code into the advisor itself; auto-loads the persona and runs your due scheduled workflows | [docs/claude-code-cockpit.md](docs/claude-code-cockpit.md) |
| **Claude Desktop** | Add InvestPal as MCP tools inside Claude Desktop | [docs/claude-desktop.md](docs/claude-desktop.md) |
| **Web UI** | Local browser app: chat with history, scheduled workflows, reminders | [docs/web-ui.md](docs/web-ui.md) |
| **Custom UI** | Build your own client using the InvestPal REST API | [docs/custom-ui.md](docs/custom-ui.md) |

---

## Prerequisites

`make setup` checks all of these and tells you what to install.

- **git**, **make**, **curl**, **nc** (pre-installed on macOS and most Linux)
- **[uv](https://docs.astral.sh/uv/)** — supplies the Python runtimes for the four service repos and for the pinned OpenBB venv at `.venvs/openbb`
- **Java** 1.8+ — only for the Interactive Brokers gateway; skip it if you are not using IB
- **Node** 20+ — only for the local web UI (`make ui`); skip it if you use the cockpit

---

## Setup

```bash
git clone https://github.com/OrestisStefanou/InvestPalEcosystem
cd InvestPalEcosystem
make setup
```

That is the whole thing. `make setup` checks prerequisites, clones the four service
repos, installs their dependencies (including the pinned OpenBB venv that serves market
data), writes your configuration, prepares the database and search index, and starts
everything. Every question it asks can be skipped with Enter. Run `make setup YES=1` to
skip them for you.

**You do not need an API key.** In the Claude Code cockpit, Claude Code is the LLM.
An LLM key is only for InvestPal's own agent — see [Backend agent](#backend-agent-optional) below.

Re-run `make setup` any time; it only does what is still missing. `make setup FORCE=1`
reconfigures from scratch.

### Configuration

Two files at the root of this repo, both gitignored, both created by `make setup`:

| File | Contents |
|---|---|
| `.env` | Ports, URLs, feature switches. See [`.env.example`](.env.example) |
| `.env.secrets` | API keys and tokens, mode 600. See [`.env.secrets.example`](.env.secrets.example) |

You never edit a `.env` inside a service repo. At start time `scripts/lib.sh` exports
the right subset of these values into each service's process, which means the settings
survive re-cloning a service repo, and the three name collisions between services
(`MCP_PORT` and `READ_ONLY` are each used by three of them) are resolved in one place.

The split is a trust boundary, not a filing system: the Claude Code agent is denied
read access to `.env.secrets` by the `permissions.deny` rules in
`.claude/settings.json`. Nothing in that file reaches Claude Code's own environment.
Each broker MCP server reads its credentials from its own process environment, which
`scripts/lib.sh` populates at start time, so a secret lives in exactly one process and
never travels over an MCP connection.

### Variable reference

Everything has a working default. The table lists what you are most likely to change;
the two example files document the rest inline.

| Variable | File | Default | Description |
|---|---|---|---|
| `MARKET_DATA_PORT` | `.env` | `8082` | Static OpenBB instance; what InvestPal's own agents use |
| `MARKET_DATA_DISCOVERY_PORT` | `.env` | `8083` | Tool-discovery OpenBB instance; what `.mcp.json` points Claude clients at |
| `TOKEN_INTENSIVE_TOOLS` | `.env` | see `.env.example` | Tools the workflow agent paces. JSON list, single-quoted |
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
| `COINBASE_API_KEY` / `COINBASE_API_SECRET` | `.env.secrets` | unset | Optional; paste the `name` and `privateKey` from Coinbase's key file as-is |
| `FRED_API_KEY` | `.env.secrets` | unset | Free, registration only. Without it commodity prices and most Fed series return nothing |
| `FMP_API_KEY` | `.env.secrets` | unset | Optional, 250 req/day free. Adds ratios, world news, estimates, peers |

### Backend agent (optional)

InvestPal ships its own LLM agent, used by the `/chat` REST endpoint, the local web
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
| `make claude` | Launch the Claude Code cockpit with `.env` loaded |
| `make start` / `make stop` | Start or stop all backend services |
| `make status` | Which services are up |
| `make doctor` | Full diagnosis of a broken or drifted install |
| `make logs` | Tail every service log |
| `make pull` | Pull the latest changes across all repos |

`make claude` loads `.env` and checks that setup has been run, but bare `claude` works
too. Brokerage keys are not needed in the cockpit's environment: the broker servers hold
their own.

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
| Market Data (OpenBB) | 8082 | Static tool set (~153 tools) at `http://localhost:8082/mcp`; InvestPal's agents use this one |
| Market Data Discovery (OpenBB) | 8083 | Tool discovery at `http://localhost:8083/mcp`; Claude Code and Claude Desktop use this one |
| AlpacaMcpServer | 9091 | Alpaca brokerage integration at `http://localhost:9091/mcp` |
| CoinbaseMcpServer | 9090 | Coinbase integration at `http://localhost:9090/mcp` |
| InteractiveBrokersMcpServer | 9092 | Interactive Brokers integration at `http://localhost:9092/mcp` |
| IB Client Portal Gateway | 5000 | Interactive Brokers' own Java gateway at `https://localhost:5000`, started only if installed |

**Startup order:** the two market-data instances start first, followed by the Alpaca, Coinbase and Interactive Brokers servers, then the InvestPal REST API and MCP App. `make start` health-gates the static market-data instance (InvestPal will not start without it) and the InvestPal MCP App, so it does not return until both are listening. The discovery instance is gated non-fatally: it only serves the Claude clients, so its failure warns rather than aborting startup. Both load the full OpenBB platform and can take up to 90 seconds on a cold start.

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
