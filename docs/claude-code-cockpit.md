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
- The InvestPal **backend services** running (see the main [README](../README.md))
- **[uv](https://docs.astral.sh/uv/)**, used by the session-start hook to talk to the MCP server

---

## What is already configured in this repo

These files make up the cockpit. They ship with the repo; you do not need to create them:

| File | Role |
|---|---|
| `.mcp.json` | Connects Claude Code to the four MCP servers (investpal, market-data, alpaca, coinbase) |
| `CLAUDE.md` | The cockpit's operating contract: client `user_id`, persona source, workflow rules, repo boundary |
| `.claude/settings.json` | Registers the `SessionStart` hook |
| `scripts/claude_cockpit/session_start.py` | The hook: loads the advisor persona and surfaces due workflows |
| `.claude/commands/run-due-workflows.md` | The `/run-due-workflows` command to re-check workflows mid-session |

---

## Step 1: Start the backend

```bash
make start
```

The MCP servers must be up *before* you launch Claude Code, because Claude Code connects to
them at startup. Wait until all services report ready (check with `make logs` if needed).

## Step 2: Launch Claude Code from this directory

```bash
cd InvestPalEcosystem
claude
```

On startup the `SessionStart` hook runs and injects two things into the session:

1. **The advisor persona**, pulled live from the InvestPal MCP prompt
   `get_invstment_advisor_prompt`, so it always matches the backend (single source of truth).
2. **Any due scheduled workflows**, with instructions for the cockpit to execute them.

Confirm the four MCP servers connected with:

```
/mcp
```

You should see `investpal`, `market-data`, `alpaca`, and `coinbase` listed as connected.

## Step 3: Use it

Just talk to it. On your first message it follows the persona: loads your profile, notes, and
reminders, surfaces anything relevant, and answers using the InvestPal skills, real-time market
data, and (if credentials are configured) your portfolio.

---

## Scheduled workflows

InvestPal owns the schedules: one cron expression per workflow, stored in the backend. The
cockpit is the **executor**:

- **At session start**, the hook asks the backend which workflows are due (`status == active`
  and `next_run_at <= now`) and tells the cockpit to run them before greeting you.
- **Mid-session**, run `/run-due-workflows` to check and execute again.
- **To run one**, the cockpit launches a subagent for the workflow's goal, stores the report
  with `storeWorkflowResult`, then advances the schedule by calling `updateAgentWorkflow` with
  the same cron string (which recomputes `next_run_at`).

> **Avoid double execution.** When the cockpit is your executor, do not also run InvestPal's
> own `/workflows/check-and-run` cron. Running both executes every workflow twice.

The cockpit only runs workflows while a Claude Code session is open (the `SessionStart` hook is
the trigger). It does not run them while Claude Code is closed.

---

## Configuration

| What | Where | Default |
|---|---|---|
| Client `user_id` | `CLAUDE.md`, and `INVESTPAL_USER_ID` env var for the hook | `orestis_user_id` |
| InvestPal MCP URL (hook) | `INVESTPAL_MCP_URL` env var | `http://127.0.0.1:9000/mcp` |
| Alpaca credentials | `ALPACA_API_KEY` / `ALPACA_API_SECRET` env vars (read by `.mcp.json`) | unset |
| Coinbase credentials | `COINBASE_API_KEY` / `COINBASE_API_SECRET` env vars (read by `.mcp.json`) | unset |

Brokerage credentials are referenced from the environment in `.mcp.json`, so no secrets are
stored in the repo. The brokerage tools list without credentials; only calling them requires
the keys.

### Placing orders

Order placement is approval-based: placing an order submits it for your approval rather than
executing immediately. The cockpit confirms your intent before submitting any order.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| Persona not loaded / advisor behaves generically | The backend was likely down at launch. Start it (`make start`), reconnect with `/mcp`, then load the persona manually with `/mcp__investpal__get_invstment_advisor_prompt`. |
| `/mcp` shows a server as failed | The corresponding service is not running, or the URL/port differs from `.mcp.json`. Check `make logs`. |
| Brokerage tool calls fail | The `ALPACA_*` / `COINBASE_*` environment variables are not set in the shell that launched Claude Code. |
| Hook error at session start | The hook always degrades safely and prints an actionable note. Run it directly to debug: `uv run --project InvestPal python3 scripts/claude_cockpit/session_start.py`. |
