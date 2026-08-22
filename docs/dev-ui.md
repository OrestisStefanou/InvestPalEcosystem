# Using the Streamlit Dev UI

The dev UI is a browser-based chat console bundled with the InvestPal service. It is intended for local development and testing — it lets you chat with the investment advisor, manage sessions, and optionally pass brokerage credentials, all from a simple web page.

---

## Prerequisites

- The InvestPal **backend services** running — `make setup` from the repo root gets you there, and `make doctor` confirms it
- **Python 3.13+**

---

## Step 1 — Install Dependencies

```bash
cd InvestPal/dev-ui

python -m venv .venv
source .venv/bin/activate        # macOS / Linux
# .venv\Scripts\activate         # Windows

pip install -r requirements.txt
```

---

## Step 2 — Configure

Open `InvestPal/dev-ui/app.py` and update the constant near the top of the file:

```python
BASE_URL = "http://localhost:8000"   # URL of the InvestPal REST API
```

InvestPal is single-user, so there is no user id to configure.

### Brokerage credentials

Nothing to configure here. The dev UI holds no credentials: brokerage keys live in the root
`.env.secrets` and are read by the Alpaca and Coinbase MCP servers themselves. With them set,
trading features work in the dev UI automatically. Without them, the app works in
conversational-only mode, and market data and advisor features are still fully available.

---

## Step 3 — Run the App

```bash
streamlit run app.py
```

Streamlit opens a browser tab at `http://localhost:8501`.

---

## Features

| Feature | Details |
|---|---|
| Chat interface | Send messages and receive AI responses |
| Session management | A new session is created automatically on first load; you can start a fresh one at any time |
| Message history | The full conversation is displayed with user / assistant styling |
| Connection status | Sidebar shows whether the backend is reachable |
| Message counter | Tracks the number of turns in the current session |

---

## Notes

- The dev UI talks directly to the InvestPal **REST API** on port 8000 — the InvestPal MCP App (port 9000) does not need to be running for the UI to work.
- The Streamlit app is not intended for production use. For a production-grade web interface, build a custom UI using the REST API (see [docs/custom-ui.md](custom-ui.md)).
