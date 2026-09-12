# Market data

Market data comes from the [OpenBB MCP server](https://github.com/OpenBB-finance/OpenBB),
which fronts 32 data providers behind one tool surface. It replaced
`MarketDataMcpServer`, the in-house Go service that scraped stockanalysis.com and
dataroma.com.

Nothing here is a hosted service. `make install` creates a pinned virtualenv at
`.venvs/openbb` (`openbb==4.7.2`, `openbb-mcp-server==1.4.1`) and `make start`
runs two instances out of it. The pins are deliberate: the category and
discovery flags used below have 1.4.1 semantics, and 1.4.x has already changed
them once.

## Two instances, because the setting is server-wide

| Service id | Port | Mode | Who talks to it |
|---|---|---|---|
| `market-data-mcp` | 8082 | Static. `--default-categories equity,etf,crypto,currency,economy,news,index,commodity,regulators`, around 153 tools, all enabled | InvestPal's REST agent and workflow agent |
| `market-data-discovery-mcp` | 8083 | `--tool-discovery`. Around 6 admin tools, all 287 reachable within a session | Claude Code cockpit and Claude Desktop, via `.mcp.json` |

Discovery mode disables every tool at startup and hands the client an
`activate_category` tool to switch groups on. That enabling is scoped to the MCP
session, so it works for a client that holds one open connection and is useless
to one that does not.

InvestPal's two agents do not. `langchain_mcp_adapters` opens a fresh session per
tool call, and `create_agent` binds a static tool list at construction time, so
on the discovery instance they would see the admin tools and never get past
them. Hence the static instance on 8082, which is the one
`MARKET_DATA_MCP_SERVER_URL` points at.

Claude Code and Claude Desktop hold a persistent session, so discovery suits
them: they start small and reach all 287 tools on demand instead of paying for
153 tool definitions in every context window. `.mcp.json` points the
`market-data` server at 8083 for exactly that reason.

Both processes load the full OpenBB platform, so both are slow to start and
neither is small in memory. `make start` allows 90 seconds each.

### Configuration

Everything about the two instances is a command-line flag set in
`scripts/start.sh`, not a file. OpenBB also reads
`~/.openbb_platform/mcp_settings.json`, but CLI beats environment beats file, so
that file is inert here and the two instances cannot collide on shared state.

One trap worth naming: `--allowed-categories` is dead configuration in 1.4.1. It
parses and is stored, and nothing ever reads it. Only `--default-categories`
has any effect, and it matches on the top-level category tag only, so there is
no subcategory granularity outside the discovery tools.

## Providers, and which ones need a key

### No key at all

Works out of the box, and covers most of what InvestPal asks for.

| Provider | Covers |
|---|---|
| `yfinance` | Prices, quotes, financial statements, key metrics, company news |
| `sec` | Filings, financial statements, Form 4 insider trading, Form 13F holdings, MD&A |
| `federal_reserve` | Treasury rates, yield curve, Fed series |
| `ecb` | Euro reference rates, euro-area yield curve |
| `imf`, `oecd` | International macro, CPI, country indicators |
| `finviz` | Screener data, key metrics, price targets |
| `cboe`, `deribit` | Options chains and derivatives |
| `finra`, `stockgrid` | Short interest, off-exchange volume |
| `tmx` | Canadian listings, ETF holdings, sector data |
| `seeking_alpha` | Earnings calendar |
| `wsj`, `multpl`, `famafrench`, `government_us` | Market movers, long-run multiples, factor returns, government data |

### Free key, registration only

| Provider | Env var | Get one at |
|---|---|---|
| **fred** | `FRED_API_KEY` | https://fredaccount.stlouisfed.org/apikeys |
| bls | `BLS_API_KEY` | https://data.bls.gov/registrationEngine/ |
| eia | `EIA_API_KEY` | https://www.eia.gov/opendata/register.php |
| cftc | `CFTC_APP_TOKEN` | https://publicreporting.cftc.gov |
| congress_gov | `CONGRESS_GOV_API_KEY` | https://api.congress.gov/sign-up/ |
| nasdaq | `NASDAQ_API_KEY` | https://data.nasdaq.com |

**Treat the FRED key as required, not optional.** `CommoditySpotPrices` and
`SpotRate` are backed by `fred` alone, so with no key commodity prices disappear
entirely. Most `economy_*` series route to fred as well, though CPI survives for
free through `imf` and `oecd`. The old Go server got these for free by scraping
`fredgraph.csv`, which is why this reads as a regression rather than a new
requirement. `make setup` asks for the key, and `make doctor` warns when it is
missing.

### Paid, or free with a low ceiling

| Provider | Env var | Note |
|---|---|---|
| **fmp** | `FMP_API_KEY` | Free tier: 250 requests/day |
| intrinio | `INTRINIO_API_KEY` | Paid |
| benzinga | `BENZINGA_API_KEY` | Paid |
| tiingo | `TIINGO_TOKEN` | Free tier, limited |
| tradingeconomics | `TRADINGECONOMICS_API_KEY` | Paid |
| alpha_vantage | `ALPHA_VANTAGE_API_KEY` | Free tier, low rate limit |
| econdb | `ECONDB_API_KEY` | Free tier |
| biztoc | `BIZTOC_API_KEY` | Paid |

**An FMP key is the single one that closes most of the gaps** left by retiring
the Go server. Without it these are unavailable at any tier:

- `equity_fundamental_ratios` (fmp and intrinio only). `equity_fundamental_metrics`
  covers part of it for free via yfinance and finviz.
- `news_world`, market news with no symbol attached. `news_company` is free via
  yfinance and tmx, so per-symbol news still works.
- `equity_fundamental_revenue_per_segment` and `_per_geography`
- `equity_estimates_*`, analyst estimates and price targets
- `equity_compare_peers`
- `equity_fundamental_transcript`, earnings-call transcripts.
  `equity_fundamental_management_discussion_analysis` is free via `sec` and gives
  written management commentary from 10-K and 10-Q filings instead.
- `equity_ownership_institutional`

### Setting a key

Put it in `.env.secrets` at the repo root, then restart market data:

```
FRED_API_KEY=your-key-here
FMP_API_KEY=your-key-here
```

```bash
make stop && make start
```

That is the whole procedure. There is no need to touch
`~/.openbb_platform/user_settings.json`: OpenBB resolves credentials from the
process environment (`openbb_core/app/model/credentials.py`), and
`scripts/lib.sh` hands these two variables to the two OpenBB processes at start
time.

The same mechanism is why `scripts/lib.sh` scrubs the environment before
launching either instance. OpenBB adopts **any** environment variable whose name
ends in `API_KEY` as a data-provider credential, and `load_env` exports the whole
of `.env.secrets` into the shell that starts the services. Without the scrub, the
Anthropic, OpenAI, Google, Alpaca and Coinbase keys would all be handed to a
process that talks to 32 third parties. Any provider key not listed above works
the same way: add it to `.env.secrets` and add its name to the whitelist in
`openbb_scrub_env`.

## What changed against the old server

Kept at parity or improved: insider transactions, financial statements, and
institutional holdings, all now from SEC filings directly rather than from a
scrape of a site that aggregates SEC filings.

Lost with no replacement: prediction-market odds (Polymarket) and crypto news.
Crypto research narrows to price history and symbol search, so do not expect
depth there.

Changed shape: `getStockOverview` fanned out to eight sources in one call. The
equivalent is now several calls (`equity_profile`, `equity_price_quote`,
`equity_fundamental_metrics`, `equity_price_performance`), which costs latency
and tokens. `getSuperInvestors` and `getSuperInvestorPortfolio` become
`regulators_sec_institutions_search` plus `equity_ownership_form_13f`: a better
source, more work for the agent, and no curated manager list.

Gained, with no equivalent before: MD&A from filings, Treasury rates and the
government yield curve, the earnings calendar, ETF holdings, index constituents,
options chains, and FOMC documents.

`calculateInvestmentFutureValue` was ported into InvestPal as a local tool, so it
survives the migration.

## Silent failures

`InvestPal/services/agents/middleware.py` swallows tool exceptions into a
`ToolMessage("Tool error: ...")`. A misconfigured or unavailable OpenBB tool
therefore fails quietly to the model rather than raising anywhere a human will
see it. When validating a change, read `logs/market-data-mcp.log` rather than
trusting agent output.

The old server annotated its own output against this (`filings_found`,
`truncated`, `matched_symbol`, "zero means not known"). OpenBB returns raw
provider data with no such framing, so that guidance now lives in the advisor
prompt instead of in the data.

## Legacy Go server (temporary)

During the changeover, `make start` can run the retired Go server alongside
OpenBB so the two can be compared answer for answer:

```
MARKET_DATA_LEGACY_ENABLED=true
MARKET_DATA_LEGACY_PORT=8084
```

Nothing points at it. InvestPal reads `MARKET_DATA_PORT`, so a rollback is one
environment variable rather than a redeploy. It needs the `MarketDataMcpServer/`
clone still on disk and a Go 1.25+ toolchain; `make clone` no longer fetches it.

**This is temporary.** When the comparison is done, set the flag to false and
delete it, along with the `market-data-legacy` block in `scripts/start.sh`, its
case in `scripts/lib.sh`, and the Go build in the `Makefile`.

## Related

- [Architecture](architecture.md)
- [Claude Code cockpit](claude-code-cockpit.md)
- [Claude Desktop](claude-desktop.md)
