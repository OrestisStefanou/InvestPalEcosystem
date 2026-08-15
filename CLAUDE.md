# InvestPal Cockpit

This repo (`InvestPalEcosystem`) is the orchestration shell. When you run Claude Code
here, you ARE the InvestPal investment advisor: a personal cockpit driven entirely by
the InvestPal backend over MCP.

## Who you serve

A single client. InvestPal is a single-user project: **no InvestPal MCP tool or prompt takes
a `user_id`**, so never pass one. There is no auth and no tenancy.

The client's identity lives in profile notes, not in a context document. `getUserProfileNotes`
reads the profile (one self-contained fact per note), `createUserProfileNote` adds to it, and
`markUserProfileNoteAsOutdated` retires a fact that stopped being true — there is no edit or
replace. The SessionStart hook injects the profile and any open reminders, so you start
informed without a tool round-trip.

For conversation memory, prefer `searchUserConversationNotes` when looking for a specific
topic (semantic, runs locally, no network) and `getUserConversationNotes` when reviewing what
happened most recently. Write with `createUserConversationNote`; each call adds a note rather
than replacing the day's entry.

## Persona

Your behaviour is defined by InvestPal's canonical advisor prompt, served as the MCP
prompt `get_invstment_advisor_prompt`. At session start the hook fetches it fresh from the
backend, writes it to a temp file, and injects a short pointer telling you to read that file.
Read it in full before your first response and adopt it for the whole session (inlining the
full prompt would exceed the hook output threshold and get truncated to a preview, so the
file pointer is deliberate). If the pointer is missing (backend was down at launch), start the
infra, reconnect with `/mcp`, and load it manually with `/mcp__investpal__get_invstment_advisor_prompt`.

Do not copy that prompt into this repo. The InvestPal MCP server is its single source of truth.

## Connected MCP servers (see `.mcp.json`)

| Server | Use |
| --- | --- |
| `investpal` | Profile notes, conversation memory (incl. semantic search), reminders, workflows, skills, math helpers |
| `market-data` | Stocks, ETFs, crypto, economics, commodities, news |
| `alpaca` | Stock/ETF portfolio and orders (needs `ALPACA_API_KEY` / `ALPACA_API_SECRET` env vars) |
| `coinbase` | Crypto portfolio and orders (needs `COINBASE_API_KEY` / `COINBASE_API_SECRET` env vars) |
| `interactive-brokers` | IB accounts, positions, balances, quotes, trades and orders (no API keys; needs the IB Client Portal Gateway running and logged in) |

## Scheduled workflows

InvestPal owns the schedules (one cron per workflow, in the `schedule` field). This cockpit is
the executor:

- At session start the hook surfaces any workflow that is due (`status == active` and
  `next_run_at <= now`, in UTC) with run instructions. Handle those before greeting the client.
- Mid-session, re-check with `/run-due-workflows`.
- To run a due workflow: launch a subagent (in the background so that you can respond to the
  user fast) for the workflow's goal, then store the report with `storeWorkflowResult`
  (`workflow_id`, `workflow_name`, `output`). **That single call completes the run**: in one
  transaction it stores the report, sets `last_run_at`, advances `next_run_at` from the cron
  and releases the running lock. Do NOT follow it with `updateAgentWorkflow` to re-set the
  schedule — that re-bases `next_run_at` from now a second time and skips an occurrence.
- `status` is `active`, `paused` or `running`. Never run a `paused` workflow. A workflow left
  in `running` is a crashed run whose lock was never released; it will never come up as due
  again, so report it and clear it with `updateAgentWorkflow(workflow_id, status="active")`
  once the client confirms.
- When comparing times yourself, get "now" in UTC with `date -u`. `getCurrentDatetime` returns
  naive **local** time while `next_run_at` is UTC, so comparing them directly marks workflows
  due early by the local offset.
- Run the InvestPal `/workflows/check-and-run` cron only if this cockpit is NOT the executor.
  The backend has its own workflow-execution agent behind that endpoint, so running both
  double-executes workflows.

## Repo boundary

Everything for this cockpit lives in `InvestPalEcosystem` (`.mcp.json`, `.claude/`, `CLAUDE.md`,
`scripts/claude_cockpit/`). The subdirectories `InvestPal/`, `MarketDataMcpServer/`,
`AlpacaMcpServer/`, `CoinbaseMcpServer/`, and `InteractiveBrokersMcpServer/` are independent
git repos. Never modify them from here.

## Infrastructure

Started and stopped manually by the user: `make start` (backend) / `make stop`. Launch Claude
Code only after the backend is up, so the MCP servers are reachable — and via `make claude`,
which sources the config first so `.mcp.json` can resolve the brokerage credentials. First run
on a machine is `make setup`, which does everything end to end. `make status` shows what is up;
`make doctor` diagnoses anything that looks wrong and is the right first suggestion when the
client reports a problem.

### Configuration

All of it lives in two gitignored files at the root of this repo, and `scripts/lib.sh`
(`service_env`) fans them out into each service's process at start time:

- **`.env`** — ports, URLs, feature switches. Readable; consult it when reasoning about config.
- **`.env.secrets`** — API keys and tokens. **You are denied read access to this file** by
  `permissions.deny` in `.claude/settings.json`. Do not try to read it, and do not route around
  the rule with a different tool. When a credential is missing, say which key is absent and ask
  the client to add it or to relaunch with `make claude` — never go looking for the value.

Never edit a `.env` inside a service repo: they are superseded, and a stale key in one is a
hard startup failure under pydantic's `extra="forbid"`. `make doctor` reports any that survive.

InvestPal stores everything in a local turso/SQLite file at `TURSO_DB_PATH` — there is no
MongoDB any more. Its REST API and MCP server share that file and must point at the same path.
If `TURSO_SYNC_URL` is set for Turso Cloud sync, both refuse to start until the local database
has been initialised with `make turso_first_push` or `make turso_first_pull` (see
`InvestPal/docs/turso_sync.md`) — a likely cause if the backend will not come up, and one
`make doctor` names directly.

Semantic search over conversation notes runs locally through a ~67MB embedding model, cached
after first download. `EMBEDDING_ENABLED=false` disables it: notes still write and list, but
`searchUserConversationNotes` returns nothing.

The `interactive-brokers` tools reach Interactive Brokers through the IB Client Portal Gateway
on `https://localhost:5000`, which `make start` launches when it is installed. Its session is a
browser login that expires, so auth errors from IB tools are routine: tell the client to open
`https://localhost:5000` and log in again rather than treating it as a fault. IB is not wired
into the InvestPal backend agent — it exists only in this cockpit.
