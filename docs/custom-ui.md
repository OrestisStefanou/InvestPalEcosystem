# Building a Custom UI

The InvestPal REST API is the integration point for any custom client application — a web app, mobile app, CLI tool, or anything else. You only need to call three endpoints in sequence to have a working chat loop.

---

## Prerequisites

- The InvestPal **backend services** running (see the main [README](../README.md))
- The InvestPal REST API is available at `http://localhost:8000` (interactive docs at `http://localhost:8000/docs`)

---

## Integration Flow

```
1. POST /user_context        → register the user (once, on first use)
2. POST /session             → open a conversation session
3. POST /chat  (loop)        → send messages and receive AI responses
```

---

## Step 1 — Register the User

```bash
curl -X POST http://localhost:8000/user_context \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "alice",
    "user_profile": {}
  }'
```

You only need to do this once per user. The user profile (`user_profile`) can be empty initially — the advisor will populate it over time as it learns about the user.

---

## Step 2 — Create a Session

```bash
curl -X POST http://localhost:8000/session \
  -H "Content-Type: application/json" \
  -d '{"user_id": "alice"}'
```

The response includes a `session_id`. Store it — you will send it with every chat message.

---

## Step 3 — Send Messages

```bash
curl -X POST http://localhost:8000/chat \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "alice",
    "session_id": "<session_id from step 2>",
    "message": "What is the current price of Apple stock?"
  }'
```

The response body contains the advisor's reply.

Repeat this call in a loop to continue the conversation. Start a new session (step 2) whenever you want to begin a fresh conversation thread.

---

## Passing Brokerage Credentials (Optional)

If you want the advisor to access a user's brokerage account, pass credentials as request headers on the `/chat` call. These are forwarded by InvestPal to the Alpaca and Coinbase MCP servers — they are never stored.

```bash
curl -X POST http://localhost:8000/chat \
  -H "Content-Type: application/json" \
  -H "X-Alpaca-Api-Key: <alpaca key>" \
  -H "X-Alpaca-Api-Secret: <alpaca secret>" \
  -H "X-Coinbase-Api-Key: <coinbase key name>" \
  -H "X-Coinbase-Api-Secret: <coinbase secret>" \
  -d '{
    "user_id": "alice",
    "session_id": "<session_id>",
    "message": "Show me my current portfolio"
  }'
```

Omit the headers entirely to run in conversational-only mode.

---

## Other Useful Endpoints

| Method | Path | Description |
|---|---|---|
| `GET` | `/user_context/{user_id}` | Read the user's saved profile |
| `PUT` | `/user_context` | Update the user's profile |
| `GET` | `/session/{session_id}` | Retrieve a session with full message history |
| `GET` | `/sessions/{user_id}` | List all sessions for a user |

---

## Full API Reference

See [`InvestPal/docs/rest_api.md`](../../InvestPal/docs/rest_api.md) for complete endpoint documentation including request/response schemas, error codes, and data types.

---

## Reference Implementations

The following existing clients in this repository show real-world usage patterns:

| Client | Location | Notes |
|---|---|---|
| Streamlit Dev UI | `InvestPal/dev-ui/app.py` | Simple Python client using `requests` |
| Telegram Bot | `InvestPalTelegramBot/agent_service_client.py` | Async Python client with session management |
