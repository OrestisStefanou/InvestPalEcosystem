# Using InvestPal with Claude Desktop

Claude Desktop can connect to the InvestPal backend services via the Model Context Protocol (MCP). Once configured, Claude has access to real-time market data, your investment advisor profile, reminders, and — optionally — your Alpaca, Coinbase and Interactive Brokers accounts, all within the normal Claude Desktop chat interface.

---

## Prerequisites

- **[Claude Desktop](https://claude.ai/download)** installed
- The InvestPal **backend services** running — `make setup` from the repo root gets you there, and `make doctor` confirms it

---

## Step 1 — Locate the Claude Desktop Config File

Open (or create) the Claude Desktop configuration file:

| Platform | Path |
|---|---|
| macOS | `~/Library/Application Support/Claude/claude_desktop_config.json` |
| Windows | `%APPDATA%\Claude\claude_desktop_config.json` |

---

## Step 2 — Add the MCP Server Entries

Edit `claude_desktop_config.json` and add (or merge) an `mcpServers` section.

### Minimal setup (conversational only — no trading)

This gives Claude access to real-time market data and the InvestPal advisor tools (user profile, memory, reminders):

```json
{
  "mcpServers": {
    "Market Data MCP Server": {
      "command": "npx",
      "args": [
        "mcp-remote",
        "http://127.0.0.1:8082/mcp"
      ]
    },
    "InvestPal MCP Server": {
      "command": "npx",
      "args": [
        "mcp-remote",
        "http://127.0.0.1:9000/mcp"
      ]
    }
  }
}
```

### Full setup (with trading access)

Add the Alpaca, Coinbase and Interactive Brokers entries to include brokerage tools. Alpaca and Coinbase credentials are passed as request headers so they never touch the server's environment; Interactive Brokers uses no credentials at all.

```json
{
  "mcpServers": {
    "Market Data MCP Server": {
      "command": "npx",
      "args": [
        "mcp-remote",
        "http://127.0.0.1:8082/mcp"
      ]
    },
    "InvestPal MCP Server": {
      "command": "npx",
      "args": [
        "mcp-remote",
        "http://127.0.0.1:9000/mcp"
      ]
    },
    "Coinbase MCP Server": {
      "command": "npx",
      "args": [
        "mcp-remote",
        "http://127.0.0.1:9090/mcp",
        "--header",
        "X-Coinbase-API-Key:${API_KEY}",
        "--header",
        "X-Coinbase-API-Secret:${API_SECRET}"
      ],
      "env": {
        "API_KEY": "<your coinbase api key name>",
        "API_SECRET": "<your coinbase api secret>"
      }
    },
    "Alpaca MCP Server": {
      "command": "npx",
      "args": [
        "mcp-remote",
        "http://127.0.0.1:9091/mcp",
        "--header",
        "X-Alpaca-Api-Key:${API_KEY}",
        "--header",
        "X-Alpaca-Api-Secret:${API_SECRET}"
      ],
      "env": {
        "API_KEY": "<your alpaca api key>",
        "API_SECRET": "<your alpaca api secret>"
      }
    },
    "Interactive Brokers MCP Server": {
      "command": "npx",
      "args": [
        "mcp-remote",
        "http://127.0.0.1:9092/mcp"
      ]
    }
  }
}
```

Replace the placeholder values with your actual credentials. If you only use one brokerage, simply omit the other entries.

The Interactive Brokers entry carries no headers: it authenticates through the IB Client Portal Gateway rather than API keys. Its tools return auth errors until that gateway is running on `https://localhost:5000` and you have logged into it in a browser.

---

## Step 3 — Restart Claude Desktop

Save the config file and fully quit and reopen Claude Desktop. The MCP servers should appear in the tool panel. If a server fails to connect, make sure the corresponding backend service is running and listening on the expected port.

---

## Step 4 — Get a Better Experience with the Advisor Prompt

The InvestPal MCP Server exposes a `get_invstment_advisor_prompt` prompt that generates a personalised system prompt for the investment advisor.

---

## Available Tools

Once connected, Claude has access to:

| Server | Tools |
|---|---|
| Market Data MCP Server | Stock/ETF/crypto quotes, company profiles, sector data, economic indicators, market news, commodity prices |
| InvestPal MCP Server | User profile (read/update), conversation notes (read/update), reminders (CRUD), advisor prompt |
| Alpaca MCP Server *(optional)* | Portfolio positions, account info, order placement |
| Coinbase MCP Server *(optional)* | Crypto portfolio, order placement |
| Interactive Brokers MCP Server *(optional)* | Accounts, positions, balances, quotes, trades, transaction history, order placement |
