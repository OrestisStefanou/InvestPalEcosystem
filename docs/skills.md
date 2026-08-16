# Skills

Skills are the analytical procedures the advisor works through. Each one is a written,
step-by-step method rather than a prompt fragment, and the advisor is instructed to reach for a
relevant skill before reasoning freehand:

> Always prefer a skill over ad-hoc analysis: skills produce more rigorous, consistent, and
> defensible answers.

> Skipping a relevant skill is a defect.

Their lineage is explicit: Graham and Dodd's *Security Analysis* for valuation and asset-based
reasoning, and Howard Marks' *The Most Important Thing* for cycles, sentiment and second-level
thinking.

## How the advisor reaches them

Two tools on the InvestPal MCP server (`:9000`):

| Tool | Purpose |
|---|---|
| `getSkillDefinitions` | Lists every skill with a short summary of what it is and when to use it |
| `getSkill` | Returns the full written procedure for one skill |

The source of truth is `InvestPal/services/agents/skills/`. Each skill is a Python module holding
the procedure text, registered in `__init__.py` through the `SkillName` enum and the
`skill_descriptions` map. The descriptions below are taken from that map, so if the two ever
disagree, the source wins.

## The fifteen skills

Grouped by the question they answer. The name in `code` is the value you pass to `getSkill`.

### Is this a good business?

#### Competitive moat

`assess_competitive_moat`

Determines whether a company is a franchise or competitive business by comparing EPV to asset value (Case A/B/C), then analyzes barriers to entry (customer captivity, cost advantages, economies of scale, and network effects) and estimates moat durability via half-life and fade rate.

*Use when the user asks about a company's competitive advantages, moat strength, or whether its growth will create or destroy value.*

#### Earnings quality

`analyze_earnings_quality`

Evaluates reported earnings across eight dimensions (cash conversion, revenue quality, cost quality, non-recurring items, tax quality, earnings consistency, transcript signals, and EPV adjustments for maintenance CapEx vs. depreciation) to detect distortions and estimate sustainable distributable earnings.

*Use when the user needs to verify the reliability of reported earnings or derive adjusted earnings power before valuation.*

#### Cash generation

`analyze_cash_flow`

Analyzes cash generation (OCF and FCF), cash quality, capital allocation decisions, and the maintenance vs. growth CapEx gap to determine owner earnings.

*Use when the user asks about a company's cash flow health, CapEx efficiency, or how management deploys cash.*

#### Balance sheet strength

`analyze_balance_sheet`

Analyzes a company's balance sheet by sector profile, evaluating liquidity, solvency, asset quality (reproduction cost vs. book value), and capital structure trends.

*Use when the user asks about a company's financial strength, asset backing, or balance sheet health.*

#### Profitability and pricing power

`analyze_income_statement`

Analyzes profitability metrics, growth quality, pricing power, and hidden growth-related investments to determine sustainable operating income using 7–15 year margin averaging.

*Use when the user asks about a company's through-cycle operational efficiency, margin sustainability, or pricing power.*

#### What management is signalling

`analyze_management_commentary`

Interprets what management is signalling about a business (guidance architecture, tone and language shifts, metric stability, attribution patterns, and the gap between stated priorities and executed capital allocation) grading how strong the underlying evidence is.

*Use when the user asks what management said about the quarter, how credible guidance is, or whether management's tone or priorities have changed.*


### What is it worth?

#### Intrinsic value

`calculate_intrinsic_value`

Performs deep Graham & Dodd valuation: calculates net asset reproduction/liquidation value, earnings power value (EPV) via a 9-step process, and return-based franchise growth value, then triangulates them and runs reasonableness checks.

*Use when the user asks for a company's intrinsic value, fair value estimate, or a detailed bottom-up valuation.*

#### Price against value

`analyze_stock_valuation`

Triangulates asset reproduction value, EPV, multiples, PEG, FCF yield, and (cautiously) DCF while accounting for market psychology, forced buying/selling, and popularity-driven mispricing.

*Use when the user asks whether a stock is cheap or expensive, wants a valuation assessment, or needs to understand price vs. intrinsic value.*

#### Against its peers

`compare_sector_peers`

Compares a target company to 3–6 sector peers across growth, profitability, valuation multiples, and balance sheet health, then ranks competitive standing.

*Use when the user asks how a company stacks up against competitors or wants to explain relative valuation premiums or discounts.*


### Should I act now?

#### Second-level thinking

`apply_second_level_thinking`

Meta-check that stress-tests an investment thesis against consensus to identify informational, analytical, behavioral, or structural edge via a 9-point checklist.

*Use when the user is considering a buy/sell decision and needs a contrarian stress-test of the thesis before acting.*

#### Market temperature

`assess_market_sentiment`

Diagnoses broad market-wide temperature by tracking the economic cycle, credit cycle, investor psychology pendulum, and bull/bear market stages using a 22-item heated-vs-cold checklist.

*Use when the user asks about overall market conditions, whether it's a good time to invest, or how to position between defensive and aggressive stances.*

#### Macro conditions

`analyze_macro_impact`

Supplementary skill that assesses how macroeconomic conditions affect a specific company's fundamentals: calibrating whether current earnings are above or below sustainable levels, adjusting cost of capital, and checking industry viability.

*Use when the user asks how interest rates, recession, inflation, or the credit cycle impact a specific stock or holding.*

#### Testing a theme

`evaluate_investment_theme`

Turns an investment theme into a falsifiable claim, maps its value chain to derive a candidate set rather than recall one, tests which link actually captures the economics, and checks how much of the theme is already in the price.

*Use when the user asks for investment ideas around a trend, theme, or narrative, or asks which companies benefit from a given development.*


### How exposed am I?

#### Portfolio risk

`analyze_portfolio_risk`

Evaluates a portfolio's aggregate risk of permanent capital loss across eight dimensions: margin of safety, business quality, leverage, concentration, liquidity, income risk, hidden correlations, and forced-selling exposure.

*Use when the user asks about their overall portfolio risk, whether they are properly diversified, or how the portfolio would survive a downturn.*

#### Margin of safety

`evaluate_margin_of_safety`

Applies defensive-investing discipline to a single position or proposed trade, checking margin of safety adequacy, upside/downside asymmetry (≥2:1), forced-selling resilience, tail-scenario survival, return reasonableness, and common pitfalls.

*Use when the user asks whether a specific trade idea is safe enough, wants to stress-test a position, or needs to validate entry price discipline.*


## Adding a skill

1. Add a module under `InvestPal/services/agents/skills/` holding the procedure text.
2. Add a member to the `SkillName` enum and an entry to `skill_descriptions` in `__init__.py`.
3. Keep the description short, and say both what the skill is and when to use it. It is what the
   advisor sees when deciding which skill applies.
4. Update this page so it stays in step with the code.

## Related

- [Architecture](architecture.md)
- [Claude Code cockpit](claude-code-cockpit.md)
