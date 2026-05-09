# Phased build plan with Claude Code prompts

This document contains the actual prompts to paste into Claude Code, in order. Each phase produces a working, testable artifact.

> **Before you start:** ensure `CLAUDE.md` is at the project root and `.claude/settings.json` is configured. Run `claude` from the project root. If you haven't already, run `claude /init` once to confirm Claude Code can read the repo.

> **Working style:** for any prompt below, prefer plan mode (Shift+Tab in Claude Code). Review the plan before letting it execute. Your job is the architect and reviewer; Claude Code is the engineer.

---

## Phase 0 — Foundation (1 session, ~30 min)

### Prompt 0.1 — Initialize the repository

```
Read CLAUDE.md fully. Then scaffold the repository structure exactly as described in section 4 of CLAUDE.md.

For each directory, create an empty .gitkeep, plus the following actual files:
- pyproject.toml at project root with: Python 3.12, ruff, mypy strict, pytest, pytest-asyncio, hypothesis, pydantic v2, structlog, httpx, boto3, decimal-context. Add tool configs.
- frontend/package.json with Next.js 14+, TypeScript strict, Tailwind, shadcn/ui, TanStack Query, zod, Recharts, Vitest, Playwright, Biome.
- .gitignore covering Python, Node, AWS CDK, IDE, secrets.
- .pre-commit-config.yaml with ruff, biome, gitleaks, the project's own block_secrets.sh hook.
- README.md (project root) — short description, link to CLAUDE.md and docs/architecture.md, quickstart commands.
- docs/architecture.md (already provided — verify it's there)
- docs/data-contracts.md (already provided — verify it's there)
- infra/local/docker-compose.yml with Postgres 16 + TimescaleDB extension, OpenSearch 2.x, MinIO.
- .github/workflows/ci.yml that runs make check + make eval-fast on every PR.
- LICENSE — MIT for now (we'll revisit).

Do not implement any agent yet. Just structure + tooling. Run `make install` and `make check` at the end to verify everything wires up.

When done, output: "Phase 0 complete. Verified: X. Open issues: Y."
```

---

## Phase 1 — Shared foundation (1-2 sessions)

### Prompt 1.1 — Schemas and base agent

```
Apply the agent-design and financial-math skills.

Implement _shared/ exactly as docs/data-contracts.md specifies:
1. _shared/schemas/base.py with StrictModel, Source, AgentOutputBase
2. _shared/schemas/instrument.py
3. _shared/schemas/portfolio.py
4. _shared/schemas/research.py
5. _shared/schemas/risk.py
6. _shared/schemas/trade.py
7. _shared/schemas/compliance.py
8. _shared/schemas/audit.py
9. _shared/decimal_context.py (sets Decimal precision, banker's rounding, imported at startup)
10. _shared/redaction.py with redact() function — handles email, account numbers, SSN-like patterns, common PII
11. _shared/llm.py — Bedrock client wrapper. Single function: invoke_model(prompt, schema, model="claude-opus-4-7", **kwargs) -> tuple[ParsedOutput, CostMetadata]. Handles retries, prompt caching, cost tracking, structured output via tool-use forcing, and emits OTel spans.
12. _shared/audit.py with @audited decorator. Wraps an async function, captures input/output (redacted), model/prompt versions, cost, duration; writes to DynamoDB + S3.
13. _shared/base_agent.py — BaseAgent[I, O] generic class. Implements: kill-switch check, audit decoration, OTel tracing, retry, timeout, guardrails. Subclass implements run() only.
14. _shared/guardrails.py with at minimum: quote_compliance() (Seeking Alpha 15-word/1-quote rule), pii_redaction(), no_specific_advice() (rejects outputs with "you should buy/sell").
15. _shared/feature_flags.py — Postgres-backed flag check.

For every module:
- Type-hint everything
- Add docstrings on public functions
- Write unit tests in the same directory; cover edge cases especially in redaction and decimal handling
- Add property tests for any function doing math (Hypothesis)

Do NOT implement any agent yet. Just the shared foundation.

Run make check before reporting done. Report coverage per module.
```

### Prompt 1.2 — Generate TS schemas + frontend skeleton

```
1. Implement scripts/generate_ts_schemas.py: walks _shared/schemas/, generates equivalent zod schemas and TS types in frontend/lib/schemas/. Use datamodel-codegen or write the generator if existing tools don't fit Pydantic v2 strict mode well.

2. Run `make schemas` to generate.

3. Build the frontend skeleton:
   - app/layout.tsx with Tailwind, basic chrome (header, nav placeholder)
   - app/page.tsx — landing → redirects to /portfolio
   - app/portfolio/page.tsx — empty dashboard
   - app/conversation/page.tsx — empty chat
   - lib/api.ts — typed API client wrapper around fetch with zod parsing
   - components/ui/ — shadcn primitives we'll need (Card, Button, Input, Dialog)

4. Create a basic agent-output-card component that takes any AgentOutputBase-shaped data and renders the layout shown in the reference screenshots (Individual_agents.pdf — already in project): summary, numbers grid, sources, caveats, cost, last-run time. This is the universal output renderer.

Run frontend tests + biome check.
```

---

## Phase 2 — Orchestrator + first specialist agent (2-3 sessions)

### Prompt 2.1 — Orchestrator skeleton

```
Apply agent-design skill.

Build agents/orchestrator/ following the agent contract:
- agent.py — OrchestratorAgent inheriting BaseAgent[OrchestratorInput, OrchestratorOutput]
- prompts/system.md (v1.0.0) — clearly states it routes to specialists, never answers from its own knowledge on financial questions, surfaces compliance blocks immediately
- schemas.py — OrchestratorInput (user message + conversation_id), OrchestratorOutput (assembled response + sub-agent outputs as structured cards)
- registry.py — agent registry with: name, kind, kill_switch_flag, A2A_endpoint, timeout_seconds, parallel_safe (bool)
- routing.py — intent classifier (Haiku) producing {intent, agents_to_invoke, parallel_or_sequential}
- aggregator.py — combines multiple agent outputs into a single coherent response with structured cards

For now, stub all specialists in the registry; the only "real" path is a passthrough that echoes input. The point is to wire up the orchestration plumbing.

Tests:
- Routing classifier on 10 example utterances
- Aggregator merges 3 mock agent outputs correctly
- Kill switch on a registered agent → orchestrator returns "agent disabled" cleanly
- Unknown intent → orchestrator asks a clarifying question, never guesses

Add the FastAPI app at agents/orchestrator/app.py exposing POST /chat that the frontend calls. Wire into make dev.
```

### Prompt 2.2 — Research Synthesis Agent (the first real specialist)

```
Apply agent-design and financial-math skills. Read CLAUDE.md section 9 (Seeking Alpha rules) carefully.

Build agents/research/ following the contract:
- agent.py — ResearchAgent
- prompts/system.md (v1.0.0)
- prompts/few_shot.md with 3 examples (one mega-cap tech, one small-cap industrial, one ambiguous case where it should request clarification)
- schemas.py — re-exports ResearchInput, ResearchOutput from _shared/schemas/research
- tools.py — registers MCP tools: sa_articles_search, sa_quant_rating, sa_author_track_record, sec_filings_get, news_search, market_data_get_fundamentals
- evals/golden.jsonl with 20 cases covering: large-cap, small-cap, foreign ADR, recent IPO, distressed name, name with conflicting SA author views
- evals/eval.py — agent-specific runner with assertions:
  * Output schema valid
  * At least 3 sources
  * Bull case + bear case both populated
  * If valuation is given, it must include method and assumptions
  * No quoted strings >15 words from any source
  * Confidence aligns with source diversity (low confidence if all sources are SA articles by one author)
- README.md with SLAs (p50: 8s, p99: 30s), accuracy target (>= 85% pass rate on golden set), kill-switch flag name (research_agent_enabled)
- test_research_agent.py — schema test, kill-switch test, redaction test, quote-compliance test, happy-path mock test

Tools (MCP servers — implement minimal versions):
- mcp_servers/seeking_alpha/server.py — implements sa_articles_search, sa_quant_rating, sa_author_track_record. Uses cookies-based auth (subscriber session), polite rate limiting (30 req/min), aggressive caching to S3, robots.txt respect. Returns structured data, never raw HTML.
- mcp_servers/filings/server.py — wraps SEC EDGAR. Implements sec_filings_get and sec_filings_search.
- mcp_servers/market_data/server.py — for now, a stub returning hardcoded fundamentals for a few tickers. We'll wire a real provider later.

Update agents/orchestrator/registry.py: research is now a real route. When the user asks for research on a ticker, orchestrator invokes ResearchAgent.

Frontend:
- Add a "Deep dive on [ticker]" CTA on the conversation surface
- Render ResearchOutput as a structured card matching the reference layout

Run make check + make eval-fast. Report eval pass rate. If <85%, list failing cases and propose hypotheses BEFORE iterating.
```

### Prompt 2.3 — Earnings & Transcript Agent

```
Apply agent-design skill.

Build agents/earnings/ following the same contract.

Specifics:
- Inputs: ticker, optional event_id (specific earnings call) or default to most recent
- Outputs (extending AgentOutputBase): guidance_extracted (structured: revenue/EPS/segments with high/mid/low and basis), management_tone_shift_vs_prior_call ("more bullish"/"more bearish"/"unchanged" with evidence quotes), analyst_questions_dodged (list of question + dodge type), surprise_topics (topics this call discussed that weren't in prior call), guidance_vs_consensus (delta in % and bps where applicable)
- Uses MCP tools: sa_transcript_get, sa_transcript_search, market_data_get_consensus, sec_filings_get
- Golden eval: 15 cases including beat/miss/in-line, guidance raise/cut/maintain, calls with notable surprises, calls in volatile sectors (semis, biotech)
- README SLAs: p50: 12s (transcript ingestion is heavy), p99: 45s

Frontend: render EarningsOutput as a card with sections for guidance, tone shift, dodged Qs, surprises.

After this agent works, you have a meaningful demo: "Tell me about NVDA's last earnings call" → earnings agent. "Should I look at NVDA?" → research agent. The two are independent; the orchestrator routes correctly.

Run make check + make eval-fast.
```

---

## Phase 3 — Portfolio context (3-4 sessions)

### Prompt 3.1 — Custodian integration + portfolio loading

```
Build mcp_servers/custodian/ with:
- A pluggable adapter pattern (CustodianAdapter ABC)
- Concrete adapters: SchwabAdapter, FidelityAdapter, IBKRAdapter (start with one — pick whichever I tell you, or default Schwab via their official API)
- For local dev: SyntheticPortfolioAdapter that produces a deterministic 30-position portfolio (large-caps + a few mid-caps + cash) for testing

Tools exposed:
- get_portfolio(account_id, as_of) -> Portfolio
- get_transactions(account_id, start, end) -> list[Transaction]
- get_lots(account_id, instrument_id) -> list[Lot]

Build data/ingestion/portfolio_snapshot.py — a daily job (Lambda + EventBridge) that:
- Calls custodian for each registered account
- Validates Portfolio schema
- Writes immutable snapshot to S3 keyed by date
- Updates Postgres with current holdings
- Emits OTel metrics

Build the Portfolio Service at agents/_services/portfolio_service.py — read-only API agents call to get the current portfolio. Caches in-memory for 60s.

Add database migrations (alembic) for:
- portfolios, positions, lots, transactions
- mandates, rules
- audit_log_index (DynamoDB-backed; this is a metadata index in Postgres for querying)
- feature_flags

Frontend: build the Portfolio surface (app/portfolio/page.tsx):
- Holdings table (sortable: ticker, weight, P&L, sector)
- Cash balances by currency
- Sector pie / treemap
- Top concentrations
- Recent transactions

Run make check + integration tests.
```

### Prompt 3.2 — Risk & Exposure Agent

```
Apply agent-design and financial-math skills. This is the agent that closes the biggest SA gap. Get this right.

Build agents/risk/ following the contract.

Implementation:
- Use Riskfolio-Lib (or PyPortfolioOpt) for v1 factor analysis. Wrap behind mcp_servers/risk_engine/ so we can swap in Axioma later.
- Factor models supported: Fama-French 3 and 5 to start. Industry-specific factors v2.
- VaR: implement historical + parametric in v1. Monte Carlo v2.
- Scenarios: implement at least these defaults — "rates_+100bps", "rates_-100bps", "spx_-20pct", "credit_spreads_+200bps", "usd_+10pct", "oil_+30pct". Configurable in YAML.
- Brinson-Fachler attribution against benchmark (sector + selection effects)
- Tracking error and active share

Schemas: RiskInput, RiskOutput per docs/data-contracts.md.

Tools: factor_analysis, var_historical, var_parametric, scenario_run, brinson_attribution, position_correlation_matrix.

Property tests (these are NON-NEGOTIABLE):
- Weights sum to 1.0 ± 0.0001
- VaR is non-negative
- Correlation matrix is positive semi-definite
- Brinson components sum to total active return (within rounding tolerance)
- Beta of benchmark vs itself is 1.0 ± 0.001

Eval: 15 cases — concentrated portfolio, diversified portfolio, all-cash, levered, FX-exposed, short-heavy.

Frontend:
- Risk panel on Portfolio surface: factor exposures (radar chart), top risk contributors (bar), VaR card, scenarios card (drag a scenario, see P&L impact)
- Click any factor → drill-in showing which positions contribute

Run all checks. Validate the property tests pass with verbose output (--hypothesis-show-statistics).
```

### Prompt 3.3 — Watchlist & Anomaly Agent

```
Apply agent-design skill.

Build agents/watchlist/.

This agent runs on a schedule (cron: every 15 min during market hours) and on-demand. It:
- Reads user's watchlist (Postgres table watchlist_items)
- For each item, checks: price moves >threshold, fundamental data changes (e.g. EPS revision), insider transactions, SA author updates (new article, rating change), unusual volume, options activity (if available)
- Produces a digest of triggers
- Emits push notifications via SNS for high-severity items

Schemas: WatchlistInput (optional filter), WatchlistOutput with triggered_items: list[Trigger].

Tools: market_data_get_quotes, sa_articles_search, sa_quant_rating, filings_recent_insider_transactions, options_unusual_activity (stub for v1).

Frontend:
- Watchlist surface (app/watchlist/page.tsx)
- Add/remove tickers
- Per-ticker trigger thresholds (price %, volume %, etc.)
- Recent triggers feed
- Push notification settings

Run make check + eval-fast.
```

---

## Phase 4 — Trade workflow with compliance (3-4 sessions)

### Prompt 4.1 — Compliance Agent (build before Trade Agent)

```
Apply agent-design skill. Read CLAUDE.md section 6 carefully — Compliance has veto power and CANNOT be bypassed. This agent is the most security-critical in the system.

Build agents/compliance/.

Specifics:
- Mandates and rules are stored in Postgres (tables: mandates, rules)
- Rule types in v1: concentration (max % of NAV per position), sector_limit (max % per GICS sector), restricted_list (no trades in specified tickers), cash_minimum (min cash %), leverage (max gross/net exposure), esg (exclusion lists)
- Pre-trade check: takes proposed trades, returns decision in {pass, warn, block} with detailed violations
- Post-trade monitoring: scans current portfolio nightly, flags drift toward limits
- Each violation references its rule_id and includes a suggested_remedy where applicable

This agent does NOT use an LLM as the rule engine — rule evaluation is deterministic Python. The LLM is used only to:
- Parse natural-language mandate text into structured Rules during onboarding
- Generate human-readable explanations of violations for the UI

Eval: 30+ cases. Include: clear blocks (restricted-list tickers, concentration breach), edge cases (would breach by 0.01%), correct passes, complex multi-rule cases.

Tests must include adversarial cases: an attacker-controlled input that tries to bypass via Unicode confusables in tickers, very large numbers, negative quantities, rule_id collisions. ALL must be handled safely.

Frontend:
- Mandates surface (app/mandates/page.tsx) — view + edit mandates (admin only)
- Compliance dashboard — current portfolio drift toward limits
- Violation card component — used wherever Compliance returns warn/block

Add the orchestrator-level enforcement: in agents/orchestrator/aggregator.py, if any sub-agent output contains a Compliance BLOCK, the orchestrator's response is the violation surface, not the requested action. This MUST be tested.

Run make check + a dedicated security test pass (`pytest tests/security/`).
```

### Prompt 4.2 — Portfolio Construction Agent

```
Apply agent-design and financial-math skills.

Build agents/portfolio/ (Portfolio Construction Agent).

Specifics:
- Inputs: list of candidate tickers (from Quant or Research), target risk profile, current portfolio, mandate constraints
- Methods supported: mean-variance optimization, risk parity, Black-Litterman, equal-weight (baseline). User picks; default mean-variance with shrinkage.
- Outputs: target weights, suggested trades (delta from current), expected portfolio metrics post-trade (factor exposures, vol, expected return, tracking error)
- Honors mandate constraints as hard constraints in the optimizer (uses CVXPY)

Tools: portfolio_state_get, factor_covariance_estimate, optimizer_run.

Property tests:
- Weights sum to 1
- All weights within [0, max_position_weight] from mandate
- Sector weights respect mandate sector_limits
- Solution is feasible OR optimizer returns infeasibility reason

Eval: 12 cases. Include: easy long-only, with sector constraints, with concentration limits, infeasible (mandate too tight), all-cash starting portfolio.

Frontend: "Suggest construction" panel that takes candidates and constraints, shows resulting allocation as before/after.
```

### Prompt 4.3 — Trade & Execution Agent (proposes only)

```
Apply agent-design skill. CRITICAL: this agent proposes trades only. Never executes autonomously. The hook block_dangerous_bash and the @audited decorator are mandatory.

Build agents/trade/.

Specifics:
- Inputs: TradeInput (portfolio_id, intent natural language, user_id)
- Internal flow:
  1. Parse intent into structured order(s)
  2. Liquidity check via market_data (ADV%, market impact estimate)
  3. Sizing check vs current portfolio
  4. CALL Compliance Agent (this is mandatory — pre_trade_check_id is recorded)
  5. If Compliance blocks → return TradeOutput with empty proposals + ComplianceResult
  6. Else return proposals + compliance pass result
- requires_approval is hardcoded True; never bypass

Tools: market_data_quote, market_data_adv, oms_dry_run (validates order would be accepted but does NOT submit).

Eval: 20 cases. Include intents like "reduce NVDA by half", "rebalance to target weights", "harvest losses", "raise 5% cash", and ambiguous ones that should request clarification.

Tests must include:
- Compliance block path → no order ticket generated
- Ambiguous intent → clarification_needed=True
- Liquidity-impossible order (e.g. selling more shares than held) → clarification + suggested alternative
- Oversized order (would be >5% of ADV) → caveat in output

Frontend:
- Approval surface (app/approvals/page.tsx) — list of pending TradeProposals, each with full rationale, expected impact, compliance result. Approve / reject buttons. Approve writes to OMS via custodian MCP. Reject logs reason.
- The Approve action itself goes through audit logging with full trail

Add an end-to-end test: user requests trade → orchestrator routes → trade agent → compliance agent → proposal returned → user approves → OMS dry run → audit entry written. Use Playwright.
```

---

## Phase 5 — Quant, Macro, News, Reporting, Tax (4-5 sessions)

### Prompt 5.1 — Quant Screening Agent

```
Apply agent-design and financial-math skills.

Build agents/quant/.

Specifics:
- Inputs: universe (e.g. "S&P 500", or list of tickers), factor weights (config), top_n
- Methods: composite factor score = weighted sum of standardized factor scores. Factors v1: value (P/E inverted, P/B inverted, EV/EBITDA inverted), quality (ROE, gross margin, debt/equity inverted), momentum (12m-1m, 6m), low-vol (1y vol inverted). Standardize cross-sectionally within universe.
- Cross-references SA Quant Rating but reports its own ranking independently. The interesting signal is disagreement.
- Output: ranked candidates with factor scores per name + composite + SA delta

Eval: 10 cases. Reproducible — use a fixed point-in-time fundamental data snapshot.

Property tests: standardized scores have mean ~0 stddev ~1 within universe; ranks are stable under weight perturbations.

Frontend: screener UI with weight sliders.
```

### Prompt 5.2 — Macro & Regime Agent

```
Apply agent-design skill.

Build agents/macro/.

Specifics:
- Pulls FRED series (rates, inflation, employment, etc.) — implement mcp_servers/macro_data/ wrapping FRED's API
- Classifies current regime across dimensions: growth (expansion/slowdown/contraction/recovery), inflation (rising/stable/falling), rates (rising/stable/falling), credit (tight/normal/loose), volatility (low/normal/high)
- Outputs scenario-conditional sector impacts

LLM use: synthesize the structured indicators into a narrative + identify regime transitions (rare but high-impact). The numerical regime classification is deterministic; the LLM provides interpretation.

Eval: 8 cases (e.g., 2008-Q3, 2020-Q2, 2022-Q4, 2024 — backtested).

Frontend: macro panel with current regime indicators + recent transition flags.
```

### Prompt 5.3 — News & Sentiment Agent

```
Apply agent-design skill.

Build agents/news/.

Specifics:
- Real-time event detection on user's holdings + watchlist
- Sources: SEC EDGAR (8-Ks especially), news APIs, SA news feed
- Uses Haiku for high-volume sentiment classification (cost discipline)
- Filters by relevance to user's portfolio (symbol match + theme match)
- Deduplicates similar stories across sources
- Outputs structured events with severity (info/notable/material) and suggested action context

Tools: news_recent, sec_8k_recent, sa_news_feed.

Eval: synthetic dataset with known-true labels (event happened or not, severity correct).

Frontend: live feed component on dashboard. Materially severe events trigger toast notifications.
```

### Prompt 5.4 — Client Reporting Agent

```
Apply agent-design skill.

Build agents/reporting/.

Specifics:
- Inputs: ReportType {ic_memo, monthly_letter, attribution_report, ad_hoc_explanation}, target audience, date range
- Pulls from portfolio history, trade history, audit log, agent outputs (research, risk)
- Generates structured documents — for v1, output is markdown that renders well; v2 add docx/pdf via the docx and pdf skills
- Enforces GIPS-style disclosures on any performance presentation
- Cites sources for all factual claims

This agent is high-leverage time-saver and is read-only on portfolio state (no write actions).

Frontend: Reports surface (app/reports/page.tsx). Generate, preview, download (markdown for v1, docx/pdf for v2).
```

### Prompt 5.5 — Tax & Transaction Agent

```
Apply agent-design and financial-math skills. Read the financial-math skill section on tax lots carefully.

Build agents/tax/.

Specifics:
- Lot-level tracking via portfolio_service
- Tax-loss harvesting opportunities: find lots at loss, propose sales, identify replacement candidates while AVOIDING wash-sale rule (30 days before/after)
- Holding period analysis (long-term vs short-term)
- Year-end planning summary
- 1099 prep helper (lot reconciliation)

Method election: per portfolio, user picks FIFO/LIFO/HIFO/Specific ID. Default FIFO.

This is high-trust math. Property tests are mandatory:
- Sum of lot quantities equals position quantity
- After a partial sale, remaining lots reconcile
- Wash sale adjustments increase replacement basis correctly
- Holding period transitions handled correctly across year-end

Frontend: Tax surface (app/tax/page.tsx) with harvesting opportunities, year-end summary, lot inspector.

Eval: 15 cases including: clean buy-sell at gain, clean buy-sell at loss, wash sale violation, partial lot sales, multi-year holding, foreign-currency cost basis.
```

---

## Phase 6 — Hardening, evals, observability (2-3 sessions)

### Prompt 6.1 — Eval harness expansion

```
Build out evals/ as a proper subsystem:
- runners/run_all.py — orchestrates per-agent runs, parallelizes safely, produces a unified report
- runners/regression.py — compares latest run to previous, flags any agent regression >3 percentage points or any schema validation failure
- datasets/ — golden datasets per agent, version controlled, with provenance comments
- reports/ — markdown + HTML reports, human-readable
- ci_gate.py — exit non-zero if regressions detected; wired into GitHub Actions

Add a dashboard (frontend/app/admin/evals/page.tsx, admin-only): per-agent pass rate over time, cost over time, latency p50/p99 over time. Use Recharts.

Backfill the golden datasets to at least 30 cases per agent. Use real market data (point-in-time snapshots committed to evals/datasets/snapshots/). For Research and Earnings agents, include 3-5 cases that are deliberately tricky (conflicting SA author views, recent management change, accounting restatement).
```

### Prompt 6.2 — Observability and runbooks

```
Implement observability:
- OTel SDK in every agent (already in BaseAgent)
- Spans for: agent.run, llm.invoke, tool.call, db.query
- Metrics: agent_invocations_total, agent_duration_seconds, agent_cost_usd, agent_failures_total
- Logs: structured JSON via structlog, redacted, request-id correlated
- Pipe to CloudWatch + Grafana

Build dashboards:
- Per-agent: invocations, p50/p99 latency, cost, failure rate
- Per-user: cost, request volume
- Compliance: blocks per day, rules triggered most often
- Trade: proposals, approvals, rejections, dollar volume

Build runbooks under docs/runbooks/:
- agent_outage.md — what to do if an agent is failing
- compliance_outage.md — trade workflow halts; safe-mode procedure
- llm_rate_limit.md — fallback model strategy
- cost_overrun.md — kill-switch procedure
- audit_query.md — how to retrieve full provenance for any output (regulator-ready)

Add alerts:
- Any agent error rate >5% over 10 min → Slack
- Any agent p99 >2x SLA target over 30 min → Slack
- Cost spike >50% above 7-day rolling average → Slack
- Compliance blocks >10/hour → Slack (anomaly)
```

### Prompt 6.3 — Security and compliance audit

```
Run /compliance-check end-to-end. Address every violation found.

Then perform a security review:
1. Threat model: who could attack this, how? Document in docs/security/threat-model.md.
2. Prompt injection defenses: any user content passed to an LLM should go through prompt_armor() in _shared/security.py — adversarial input wrapping with delimiters and explicit instructions.
3. SA cookie safety: subscriber session cookies stored encrypted in Secrets Manager, never logged, never returned in API responses.
4. PII handling: complete walkthrough — onboarding, storage, processing, retention, deletion. Document in docs/security/pii.md.
5. SOC 2 readiness checklist (we won't be SOC 2 compliant in v1, but track the gap): docs/security/soc2-gap.md.

Add tests/security/ with: prompt injection cases, PII leakage cases, audit log tampering attempts, compliance bypass attempts. ALL must pass.
```

---

## Phase 7 — Production readiness (2 sessions)

### Prompt 7.1 — CDK stacks and deployment

```
Build infra/ (AWS CDK Python):
- stacks/agentcore_stack.py — AgentCore Runtime deployments for each agent, A2A configuration, Memory, Gateway with MCP servers, Identity, Observability, Evaluations
- stacks/data_stack.py — RDS PostgreSQL with Timescale, OpenSearch, S3 buckets (audit, snapshots, articles, reports), DynamoDB (audit hot path), Secrets Manager
- stacks/frontend_stack.py — Next.js on App Runner or ECS, CloudFront, Cognito + Okta SAML
- stacks/observability_stack.py — CloudWatch dashboards, alarms, Grafana workspace

Three environments: dev, staging, prod. Parameterize via context.

CI/CD via GitHub Actions:
- On PR: make check, eval-fast, security tests
- On merge to main: deploy to dev
- Manual approval: deploy to staging
- Manual approval + change ticket: deploy to prod

Add deploy.sh helper for dev environment.

Test the full deploy in dev. Document the runbook for staging promotion.
```

### Prompt 7.2 — Onboarding flow + first user

```
Build the onboarding surface (frontend/app/onboarding/):
- Step 1: connect custodian (OAuth flow per adapter)
- Step 2: connect Seeking Alpha (subscriber credentials → encrypted → Secrets Manager)
- Step 3: define mandate (NL input → Compliance Agent parses → user confirms structured rules)
- Step 4: import portfolio (one-time backfill of holdings + transactions)
- Step 5: set risk tolerance and reporting preferences

Add a "tour" that walks the new user through:
- Asking the orchestrator a research question
- Reviewing the generated thesis
- Adding the ticker to a watchlist
- Reviewing risk dashboard
- Generating an IC memo

This is the demo experience. Make it feel polished.

Run a full end-to-end Playwright test of this flow. Fix every rough edge.
```

---

## Working with Claude Code: meta-tips

1. **One task per session.** When a session is "done", run `/context-checkpoint` and `/clear`. Fresh context is faster context.
2. **Plan mode for any 3+ file change.** Shift+Tab. Review the plan. Edit if needed. Then proceed.
3. **Run `/compliance-check` before merging anything that touches agents/, mcp_servers/, or _shared/.**
4. **When Claude makes a mistake worth not repeating, add to CLAUDE.md section 16.** This is how the system gets smarter over time.
5. **Don't let context exceed 60%.** Performance degrades. Checkpoint and reset.
6. **Schemas before logic, always.** If I ever see Claude implementing logic before schema, I stop it.
7. **Use the smallest model that works.** The default model in settings.json is Opus 4.7 for hard reasoning, but for boilerplate work (TS components, simple CRUD), drop to Sonnet 4.6 with `--model claude-sonnet-4-6`.
8. **Trust but verify.** Every PR gets human review for: schema correctness, audit decoration, financial math, compliance enforcement. The hooks catch the worst; humans catch the rest.
