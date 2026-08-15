# Using InvestPal as a Claude Code Cockpit

Run [Claude Code](https://claude.com/claude-code) from inside this repo (`InvestPalEcosystem`)
and it *becomes* the InvestPal investment advisor: a personal cockpit driven entirely by
the InvestPal backend over MCP. It loads InvestPal's canonical advisor persona automatically,
has the full market-data and brokerage toolset, and acts as the executor for your scheduled
workflows.

## How this differs from Claude Desktop

Both connect to the same MCP servers, but they are used differently:

| | Claude Desktop | Claude Code cockpit |
|---|---|---|
| What it is | A general chat with InvestPal tools added | This repo turned into the advisor itself |
| Persona | You drive the conversation | Loads InvestPal's canonical advisor prompt automatically at session start |
| Scheduled workflows | Not executed | Surfaces and runs any due workflows on session start (and on demand) |
| Best for | Occasional questions inside a normal Claude chat | A power-user / personal advisor terminal |

The cockpit is configured entirely within this repo. Nothing in the nested service repos
(`InvestPal/`, `MarketDataMcpServer/`, etc.) is modified.

---

## Prerequisites

- **[Claude Code](https://claude.com/claude-code)** installed
- The InvestPal **backend services** running — `make setup` from the repo root gets you there, and `make doctor` confirms it
- **[uv](https://docs.astral.sh/uv/)**, used by the session-start hook to talk to the MCP server

---

## What is already configured in this repo

These files make up the cockpit. They ship with the repo; you do not need to create them:

| File | Role |
|---|---|
| `.mcp.json` | Connects Claude Code to the five MCP servers (investpal, market-data, alpaca, coinbase, interactive-brokers) |
| `CLAUDE.md` | The cockpit's operating contract: memory model, persona source, workflow rules, repo boundary |
| `.claude/settings.json` | Registers the `SessionStart` hook |
| `scripts/claude_cockpit/session_start.py` | The hook: loads the advisor persona, the client profile and reminders, and surfaces due workflows |
| `.claude/commands/run-due-workflows.md` | The `/run-due-workflows` command to re-check workflows mid-session |

---

## Step 1: Start the backend

```bash
make start
```

First time on this machine, run `make setup` instead — it installs everything, writes your
configuration and starts the stack in one go. See the main [README](../README.md#setup).

The MCP servers must be up *before* you launch Claude Code, because Claude Code connects to
them at startup. `make start` does not return until the InvestPal MCP app is listening, and
`make status` shows what is up at any time.

## Step 2: Launch Claude Code from this directory

```bash
cd InvestPalEcosystem
make claude
```

Use `make claude` rather than bare `claude`. It sources `.env` and `.env.secrets` before
launching, which is what lets `.mcp.json` resolve `${ALPACA_API_KEY}` and friends into the
request headers the brokerage servers expect. Launched without it, the brokerage tools list
but fail when called.

On startup the `SessionStart` hook runs and injects three things into the session:

1. **The advisor persona**, pulled live from the InvestPal MCP prompt
   `get_invstment_advisor_prompt`, so it always matches the backend (single source of truth).
   It is written to a temp file and the hook injects the path, because inlining the full prompt
   exceeded Claude Code's inline-output threshold and got truncated to a preview.
2. **Your profile notes and open reminders**, so the first answer is already informed by them.
3. **Any due scheduled workflows**, with instructions for the cockpit to execute them.

Confirm the five MCP servers connected with:

```
/mcp
```

You should see `investpal`, `market-data` and `interactive-brokers` connected. `alpaca` and
`coinbase` are opt-in: `make setup` enables each one in `.claude/settings.local.json` when you
give it that brokerage's credentials, so if they are missing here you either skipped that
question or the keys are not in `.env.secrets`. `interactive-brokers` needs no keys, but its
tools fail until the IB Client Portal Gateway is running and logged in.

## Step 3: Use it

Just talk to it. Your profile and reminders are already in context from the hook; on your first
message it follows the persona, recalls relevant past conversations (semantically, via
`searchUserConversationNotes`), and answers using the InvestPal skills, real-time market data,
and (if credentials are configured) your portfolio.

---

## Scheduled workflows

InvestPal owns the schedules: one cron expression per workflow, stored in the backend. The
cockpit is the **executor**:

- **At session start**, the hook asks the backend which workflows are due (`status == active`
  and `next_run_at <= now`, compared in UTC) and tells the cockpit to run them before greeting
  you.
- **Mid-session**, run `/run-due-workflows` to check and execute again.
- **To run one**, the cockpit launches a subagent for the workflow's goal and stores the report
  with `storeWorkflowResult`. That call also *completes* the run: in one transaction it records
  `last_run_at`, advances `next_run_at` from the cron schedule and releases the running lock.
  Nothing else touches the schedule.
- **A workflow stuck in `running`** is a run that died before storing a result. Its lock was
  never released, so it will never come up as due again. The hook reports these, and they are
  cleared with `updateAgentWorkflow(workflow_id, status="active")`.

> **Avoid double execution.** When the cockpit is your executor, do not also run InvestPal's
> own `/workflows/check-and-run` cron. The backend has its own workflow-execution agent behind
> that endpoint, so running both executes every workflow twice.

The cockpit only runs workflows while a Claude Code session is open (the `SessionStart` hook is
the trigger). It does not run them while Claude Code is closed.

---

## Configuration

| What | Where | Default |
|---|---|---|
| Everything else | `.env` at the repo root, fanned out into each service at start time | see `.env.example` |
| InvestPal MCP URL (hook) | `INVESTPAL_MCP_URL` env var | `http://127.0.0.1:9000/mcp` |
| Alpaca credentials | `ALPACA_API_KEY` / `ALPACA_API_SECRET` in `.env.secrets`, exported by `make claude` | unset |
| Coinbase credentials | `COINBASE_API_KEY` / `COINBASE_API_SECRET` in `.env.secrets`, exported by `make claude` | unset |
| Interactive Brokers session | Browser login at `https://localhost:5000` — no keys anywhere | not authenticated |

Credentials live in `.env.secrets`, which is gitignored, mode 600, and denied to the agent by
the `permissions.deny` rules in `.claude/settings.json`. `.mcp.json` reads them from the
environment rather than from any file, which is why `make claude` exists. The brokerage tools
list without credentials; only calling them requires the keys.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| Anything at all | Run `make doctor` first. It checks the toolchain, config coherence, port agreement with `.mcp.json`, every service, the database and secret hygiene, and prints a fix for each problem. |
| Persona not loaded / advisor behaves generically | The backend was likely down at launch. Start it (`make start`), reconnect with `/mcp`, then load the persona manually with `/mcp__investpal__get_invstment_advisor_prompt`. |
| `/mcp` shows a server as failed | The corresponding service is not running, or the URL/port differs from `.mcp.json`. Check `make logs`. |
| InvestPal will not start at all | If `TURSO_SYNC_URL` is set, both InvestPal servers refuse to start until the local database is initialised with `make turso_first_push` or `make turso_first_pull` (see `InvestPal/docs/turso_sync.md`). Run `make turso_status` to see which applies. |
| A workflow stopped running entirely | It is probably stuck in `status = running` after a crashed run. The hook reports these; clear it with `updateAgentWorkflow(workflow_id, status="active")`. |
| `searchUserConversationNotes` returns nothing | Either `EMBEDDING_ENABLED=false`, or the notes predate the current embedding model. Run `make backfill_embeddings` in `InvestPal/`. |
| Brokerage tool calls fail | Claude Code was launched without the credentials in its environment. Quit and relaunch with `make claude`. |
| `interactive-brokers` tools return an auth error | The IB Client Portal Gateway is down or its session expired. `make start` reports both; open `https://localhost:5000` and log in again. |
| Hook error at session start | The hook always degrades safely and prints an actionable note. Run it directly to debug: `uv run --project InvestPal python3 scripts/claude_cockpit/session_start.py`. |
