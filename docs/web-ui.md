# The local web UI

A browser app for InvestPal: chat with full session history, scheduled workflows and
their past reports, and the reminders the agent is holding for you. It runs on your
machine and talks to the InvestPal REST API on `localhost`. Nothing is hosted, and there
is no account.

It replaces the Streamlit dev console, which only ever covered two of the eleven REST
endpoints and was never wired into `make setup`.

---

## Two things to know first

**It needs Node.** Nothing else in this stack does. `make setup` does not install it and
does not ask for it, and `make doctor` reports its absence as information rather than a
failure. If you use the Claude Code cockpit, you never need Node at all.

**Chat needs an AI provider key.** This is the one thing people hit on a fresh install.
The chat view calls `POST /chat`, which runs *InvestPal's own* agent, so it needs
`ANTHROPIC_API_KEY` (or the OpenAI/Google equivalent) in `.env.secrets`, matching
`LLM_PROVIDER` in `.env`. `make setup` defaults that question to no, so on a stock install
every view works except chat.

The Claude Code cockpit is different: there, Claude Code is the model, so no key is
involved. That is why a key is optional for the stack as a whole but required for this app.

---

## Running it

```bash
make start      # the backend services, if they are not already up
make ui         # the web UI on http://localhost:5173
```

The first `make ui` installs the app's dependencies; later runs skip that. You never need
to type `npm` yourself.

| Command | What it does |
|---|---|
| `make ui` | Start the UI, installing dependencies on first run |
| `make ui_stop` | Stop only the UI |
| `make stop` | Stop everything, the UI included |
| `make status` | Shows the UI only while it is running |

Output goes to `logs/investpal-web.log`.

Only the REST API on port 8000 has to be running. The InvestPal MCP app on port 9000 is
for MCP clients such as Claude Code, and this app does not use it.

---

## What each view covers

| View | Endpoints | Notes |
|---|---|---|
| Chat | `POST /session`, `GET /sessions`, `GET /session/{id}`, `POST /chat` | Session list with real history. Opens your most recent session on load |
| Workflows | `GET`/`POST /workflows`, `PATCH`/`DELETE /workflows/{id}`, `GET /workflow_results` | Create, pause, resume, delete, and read past reports |
| Reminders | `GET /agent_reminders` | Read-only, see below |

**Reminders are read-only** because the REST API has no way to create one: the agent
creates reminders through the MCP server while you are talking to it. Ask InvestPal to
remember something and it shows up here.

**The UI never calls `POST /workflows/check-and-run`.** The Claude Code cockpit is the
workflow executor; calling that endpoint as well runs every due workflow twice.

---

## Waiting for a reply

`POST /chat` blocks for the whole agent run, which is routinely minutes. There is no
streaming endpoint, so there is nothing to show until the answer is complete. The UI shows
a panel with the real elapsed time and says as much, rather than drawing a progress bar it
cannot fill.

"Stop waiting" stops this tab waiting. The agent carries on server-side and its reply is
still written to the session, so a reload will show it.

The agent only sees the most recent messages in a session, set by
`CONVERSATION_MESSAGES_LIMIT` in `.env` (default 15). That is why it stops recalling the
top of a very long thread.

---

## When something fails

The API returns no CORS headers on a 5xx, only on success. So when InvestPal errors, the
browser blocks the response and the app cannot see the status code: "cannot reach
InvestPal" covers both *not running* and *running but failing*. The real error is always in
`logs/investpal-api.log`.

| Symptom | Usual cause |
|---|---|
| Every view says it cannot reach InvestPal | Backend not running. `make start` |
| Only chat fails, everything else loads | No provider key in `.env.secrets` |
| Port 5173 already in use | Another dev server. `make ui_stop`, or change `INVESTPAL_WEB_PORT` in `.env` |
| `node`/`npm` not found | Node is not installed; see above |

`make doctor` names all of these.

---

## Design

The app deliberately shares its design tokens with the public site at
<https://orestisstefanou.github.io/investpal/>. `investpal-web/src/styles/tokens.css` is
copied from that page's stylesheet; change a colour there first, then re-copy. The theme
choice is stored under the same `localStorage` key (`ip-theme`), so a theme set on the site
carries over.

Fonts are self-hosted in `investpal-web/public/fonts/` rather than linked from Google
Fonts, so the app makes no network call of its own.

---

## Building on the REST API instead

To write your own client, see [custom-ui.md](custom-ui.md). The typed client in
`investpal-web/src/api/` covers all ten endpoints this app uses and is the reference
implementation.
