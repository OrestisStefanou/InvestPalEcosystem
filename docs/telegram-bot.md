# Using InvestPal via Telegram

The Telegram Bot lets you chat with the InvestPal AI advisor directly from the Telegram mobile or desktop app — no additional web interface required.

---

## Prerequisites

- The InvestPal **backend services** running (see the main [README](../README.md))
- **Python 3.13+** and **[uv](https://docs.astral.sh/uv/)**
- A **Telegram account**
- **[ngrok](https://ngrok.com/)** (or another tunneling tool) for local development — the bot requires a publicly reachable HTTPS URL for Telegram webhooks

---

## Step 1 — Create a Telegram Bot via BotFather

1. Open Telegram and search for **@BotFather** (or follow [t.me/BotFather](https://t.me/BotFather)).
2. Start a conversation and send the command `/newbot`.
3. BotFather will ask for a **name** (display name, e.g. *My InvestPal*) and a **username** (must end in `bot`, e.g. `my_investpal_bot`).
4. Once created, BotFather sends a message containing your **bot token** — a long string like `123456:ABCdefGhIjKlMnOpQrStUvWxYz`. Copy it.

> Keep the token secret. Anyone who has it can control your bot.

---

## Step 2 — Find Your Telegram User ID

The bot is configured to respond only to a single user (you). To find your Telegram user ID:

1. Open Telegram and search for **@userinfobot** (or follow [t.me/userinfobot](https://t.me/userinfobot)).
2. Start a conversation — the bot immediately replies with your **Id** (a numeric value like `123456789`). Copy it.

---

## Step 3 — Set Up ngrok (Local Development)

Telegram needs to reach your bot over a public HTTPS URL. For local development, use ngrok to create a tunnel to your machine:

```bash
# Install ngrok from https://ngrok.com/download, then:
ngrok http 8443
```

ngrok prints an HTTPS URL like `https://xxxx.ngrok-free.app`. Copy it — this becomes your `TELEGRAM_WEBHOOK_URL`.

> You need to restart ngrok each time you restart your machine, and update `TELEGRAM_WEBHOOK_URL` in the `.env` file with the new URL.

---

## Step 4 — Configure the Bot

Create `InvestPalTelegramBot/.env` with the values gathered above.

### Minimal setup (conversational only — no trading)

```env
# From BotFather
TELEGRAM_BOT_TOKEN=your_bot_token_here

# Your ngrok HTTPS URL (or production domain)
TELEGRAM_WEBHOOK_URL=https://xxxx.ngrok-free.app

# Port the bot listens on locally
TELEGRAM_WEBHOOK_PORT=8443

# Your Telegram user ID (from @userinfobot)
TELEGRAM_USER_ID=your_telegram_user_id

# URL of the InvestPal REST API
INVESTPAL_BACKEND_URL=http://127.0.0.1:8000
```

With this configuration the agent has access to real-time market data and all conversational features (memory, reminders, user profile) but cannot access any brokerage account.

### Full setup (with trading access)

Add the brokerage credentials to the `.env` file above:

```env
# Alpaca Markets (https://alpaca.markets)
ALPACA_API_KEY=your_alpaca_key
ALPACA_API_SECRET=your_alpaca_secret

# Coinbase (https://www.coinbase.com/settings/api)
COINBASE_API_KEY=your_coinbase_key_name
COINBASE_API_SECRET=your_coinbase_key_secret
```

The agent will then be able to read your portfolio holdings and place orders.

---

## Step 5 — Start the Services

From inside the `InvestPalEcosystem/` directory:

```bash
# Make sure ngrok is already running and TELEGRAM_WEBHOOK_URL is set, then:
make start-all
```

This starts the full backend (MarketDataMcpServer → AlpacaMcpServer → CoinbaseMcpServer → InvestPal API → InvestPal MCP) and then the Telegram bot.

To stop everything:

```bash
make stop
```

---

## Usage Tips

- Open your bot in Telegram (search for the username you gave it in BotFather) and start chatting.
- The bot maintains a persistent session, so the advisor remembers context within the conversation.
- If the backend is restarted the session continues automatically on the next message.
