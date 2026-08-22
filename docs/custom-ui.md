# Building a Custom UI

The InvestPal REST API is the integration point for any custom client application — a web app, mobile app, CLI tool, or anything else. You only need to call two endpoints in sequence to have a working chat loop.

InvestPal is a **single-user** application. There is no `user_id` anywhere in the API, no user registration step, and no authentication.

---

## Prerequisites

- The InvestPal **backend services** running — `make setup` from the repo root gets you there, and `make doctor` confirms it
- The InvestPal REST API is available at `http://localhost:8000` (interactive docs at `http://localhost:8000/docs`)

---

## Integration Flow

```
1. POST /session             → open a conversation session
2. POST /chat  (loop)        → send messages and receive AI responses
```

---

## Step 1 — Create a Session

```bash
curl -X POST http://localhost:8000/session \
  -H "Content-Type: application/json" \
  -d '{"name": "Portfolio review"}'
```

Both fields are optional: omit `session_id` and one is generated, omit `name` and the `session_id` is used as the name. Responds `201` with the full session; store its `session_id` and send it with every chat message. `409` means that `session_id` already exists.

---

## Step 2 — Send Messages

```bash
curl -X POST http://localhost:8000/chat \
  -H "Content-Type: application/json" \
  -d '{
    "session_id": "<session_id from step 1>",
    "message": "What is the current price of Apple stock?"
  }'
```

The response body is `{"response": "..."}` with the advisor's reply. `404` means the session does not exist.

Repeat this call in a loop to continue the conversation. Start a new session (step 1) whenever you want to begin a fresh conversation thread.

---

## Brokerage Credentials

Your client passes no credentials. Brokerage keys live in the root `.env.secrets` and are read
by the Alpaca and Coinbase MCP servers themselves, so a plain `/chat` call reaches the brokerage
tools with no extra headers:

```bash
curl -X POST http://localhost:8000/chat \
  -H "Content-Type: application/json" \
  -d '{
    "session_id": "<session_id>",
    "message": "Show me my current portfolio"
  }'
```

With no keys configured the advisor runs in conversational-only mode: the broker servers
register no tools, so it simply has none to call.

---

## Other Useful Endpoints

| Method | Path | Description |
|---|---|---|
| `GET` | `/session/{session_id}` | Retrieve a session with full message history |
| `GET` | `/sessions` | List all sessions |
| `GET` | `/agent_reminders` | List open reminders |
| `POST` | `/workflows` | Create a cron-scheduled workflow (`name`, `description`, `schedule`) |
| `GET` | `/workflows` | List workflows |
| `PATCH` | `/workflows/{workflow_id}` | Update a workflow (`name`, `description`, `schedule`, `status`) |
| `DELETE` | `/workflows/{workflow_id}` | Delete a workflow; its past results are kept |
| `POST` | `/workflows/check-and-run` | Heartbeat: claim and execute any due workflows. Intended for an external cron |
| `GET` | `/workflow_results` | Results of past workflow runs, most recent first (`?limit=10`) |

The user's profile and conversation memory are not on the REST API — they are managed by the advisor itself over MCP (`getUserProfileNotes`, `createUserProfileNote`, `searchUserConversationNotes`, …). See [`InvestPal/docs/mcp_api.md`](../InvestPal/docs/mcp_api.md).

> Call `POST /workflows/check-and-run` only if nothing else is executing workflows. The Claude Code cockpit executes them too; running both double-executes every workflow.

---

## Full API Reference

See [`InvestPal/docs/rest_api.md`](../InvestPal/docs/rest_api.md) for complete endpoint documentation including request/response schemas, error codes, and data types.

---

## Reference Implementations

The following existing clients in this repository show real-world usage patterns:

| Client | Location | Notes |
|---|---|---|
| Web UI | `investpal-web/src/api/` | Typed TypeScript client over `fetch`, covering all ten endpoints. See [web-ui.md](web-ui.md) |
