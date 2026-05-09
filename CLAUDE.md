# CLAUDE.md — Agentic Asset Management Platform

You are working on a multi-agent AI platform that acts as a co-worker for an asset manager. The user's primary research source is Seeking Alpha; the platform fills the gaps SA does not cover (portfolio-level risk, attribution, compliance, execution, reporting) and integrates SA content into a structured agentic workflow.

This file is the persistent context. Read it carefully on every session. When you make a mistake or learn something new about the codebase, propose an addition to this file.

---

## 1. Project mission

Build a production-grade multi-agent system where each agent owns one well-defined function. An orchestrator routes the asset manager's requests to specialist agents. Every recommendation is traceable to its sources, prompts, model versions, and data snapshots. Nothing that touches money executes without human approval.

**Non-goals (do not build these):**
- Auto-execution of trades. Trade agent proposes; human approves.
- A general-purpose chatbot. Each agent has a narrow job.
- A replacement for SA. SA is an input source, not a competitor.
- HFT / sub-second latency. Target latency is seconds, not microseconds.

---

## 2. Architecture at a glance

```
Portfolio Manager (web UI)
        ↓
Orchestrator Agent  ←→  Memory + Audit Log
        ↓
12 Specialist Agents (each one job, structured I/O)
        ↓
Shared Services (vector DB, eval harness, guardrails)
        ↓
Data Sources (SA, market data, alt data, custodian/OMS)
```

The 12 agents:
1. Research Synthesis — thesis docs from SA + filings
2. Quant Screening — factor-based candidate ranking
3. Risk & Exposure — VaR, factor exposures, stress tests
4. Earnings & Transcript — call analysis, guidance extraction
5. Macro & Regime — rates/FX/inflation regime classification
6. News & Sentiment — real-time event monitoring
7. Portfolio Construction — sizing, optimization
8. Trade & Execution — pre-trade checks, order generation (proposes only)
9. Compliance — mandate/IPS limit monitoring
10. Client Reporting — IC memos, attribution, client letters
11. Tax & Transaction — lot tracking, harvesting
12. Watchlist & Anomaly — monitoring of non-held names

---

## 3. Tech stack (locked — do not change without discussion)

- **Runtime:** Amazon Bedrock AgentCore (Runtime, Memory, Gateway, Identity, Observability, Evaluations)
- **Models:** Claude Opus 4.7 for reasoning-heavy agents (Research, Portfolio, Compliance, Risk); Claude Sonnet 4.6 for routine agents (News, Watchlist, Earnings); Claude Haiku 4.5 for high-volume low-latency (sentiment classification)
- **Inter-agent protocol:** A2A (Agent-to-Agent) for specialist↔specialist; orchestrator uses both A2A and direct HTTP
- **Tool integration:** MCP (Model Context Protocol) servers behind AgentCore Gateway
- **Agent framework:** Strands Agents SDK as default; LangGraph allowed where state machines are clearer
- **Language:** Python 3.12 for agents and backend; TypeScript for frontend
- **Data layer:** PostgreSQL (relational/transactional), TimescaleDB extension (time-series), OpenSearch (vector + lexical), S3 (raw documents)
- **Frontend:** Next.js 14+ App Router, Tailwind, shadcn/ui, TanStack Query, Recharts
- **Auth:** AWS Cognito + Okta SAML for enterprise SSO
- **Infra-as-code:** AWS CDK (Python). No raw CloudFormation.
- **CI/CD:** GitHub Actions → CodeBuild → AgentCore deployment
- **Testing:** pytest + pytest-asyncio + hypothesis (Python); Vitest + Playwright (TS)
- **Observability:** AgentCore Observability + OpenTelemetry → CloudWatch + Grafana
- **Eval harness:** AgentCore Evaluations + custom benchmarks (golden dataset, per-agent)

---

## 4. Repository structure

```
asset-mgmt/
├── CLAUDE.md                       # This file
├── .claude/
│   ├── settings.json               # Permissions, hooks
│   ├── commands/                   # Custom slash commands
│   └── skills/                     # Reusable skills
├── docs/
│   ├── architecture.md             # System design, ADRs
│   ├── agents/                     # One md per agent: I/O schema, prompts, evals
│   ├── data-contracts.md           # All Pydantic schemas as canonical reference
│   ├── runbooks/                   # Operational runbooks
│   └── compliance.md               # Regulatory + audit requirements
├── infra/                          # AWS CDK stacks
│   ├── stacks/
│   │   ├── agentcore_stack.py
│   │   ├── data_stack.py
│   │   ├── frontend_stack.py
│   │   └── observability_stack.py
│   └── app.py
├── agents/                         # One package per agent
│   ├── _shared/                    # Common code: schemas, memory, guardrails
│   │   ├── schemas/                # Pydantic models, ALL agent I/O
│   │   ├── memory.py
│   │   ├── guardrails.py
│   │   ├── audit.py
│   │   └── llm.py                  # Bedrock client wrapper
│   ├── orchestrator/
│   ├── research/
│   ├── quant/
│   ├── risk/
│   ├── earnings/
│   ├── macro/
│   ├── news/
│   ├── portfolio/
│   ├── trade/
│   ├── compliance/
│   ├── reporting/
│   ├── tax/
│   └── watchlist/
├── mcp_servers/                    # MCP servers for tool access
│   ├── seeking_alpha/
│   ├── market_data/
│   ├── custodian/
│   ├── filings/
│   └── risk_engine/
├── data/                           # Data ingestion + ETL
│   ├── ingestion/
│   ├── transforms/
│   └── snapshots/                  # Daily portfolio snapshots
├── frontend/                       # Next.js app
│   ├── app/
│   ├── components/
│   └── lib/
├── evals/                          # Eval harness + golden datasets
│   ├── datasets/
│   ├── runners/
│   └── reports/
├── scripts/                        # One-off scripts
└── tests/
    ├── unit/
    ├── integration/
    └── e2e/
```

---

## 5. Code style and conventions

### Python
- **Format with Ruff** (`ruff format`). Lint with Ruff (`ruff check --fix`). Both run in pre-commit.
- **Type-hint everything.** Functions with no annotations fail CI. Use `from __future__ import annotations`.
- **Pydantic v2** for ALL agent input and output schemas. No untyped dicts crossing agent boundaries — ever.
- **Async by default** for I/O. Use `asyncio` and `httpx`. Never use `requests` in agent code.
- Use `structlog` for logging. Every log line includes `agent_name`, `request_id`, `user_id`.
- Constants go in `_shared/constants.py`. No magic numbers in agent logic.
- Imports: stdlib, third-party, first-party. Ruff enforces.
- File names: `snake_case.py`. Class names: `PascalCase`. Functions and variables: `snake_case`.
- Tests live next to code: `agents/research/research_agent.py` → `agents/research/test_research_agent.py`. Integration tests under `/tests`.

### TypeScript
- Strict mode on. `noUncheckedIndexedAccess: true`. No `any` without `// reason: …` comment.
- Format with Biome. Lint with Biome.
- Prefer `function` declarations for components, arrow functions for callbacks.
- Use `zod` for runtime validation of API responses; mirror Pydantic schemas exactly.
- Never use `localStorage` for sensitive data. Use httpOnly cookies via Cognito.

### General
- **Files under 400 lines.** If larger, split. Long files signal a missing abstraction.
- **Functions under 50 lines.** Same logic.
- **Cyclomatic complexity under 10.** Ruff/Biome will warn.
- Naming reveals intent. `compute_factor_exposure_for_portfolio()` not `cfe()`.

---

## 6. Critical rules (these are non-negotiable)

These are the rules that, if violated, create regulatory, financial, or trust incidents. CLAUDE.md is advisory and followed ~70% of the time, so the most important of these are also enforced by hooks and CI.

1. **No agent autonomously executes trades.** The Trade Agent ALWAYS proposes; a human ALWAYS approves through the UI. There is a hook that blocks any code path with `execute_order` not gated by `approval_required=True`.
2. **Every agent output goes through the Audit Log.** Use `@audited` decorator. Includes inputs, outputs, model name, model version, prompt version, data snapshot ID, timestamp, user ID. Immutable, append-only, S3 + DynamoDB.
3. **No PII in logs.** Use `_shared/redaction.py` `redact()` before logging anything that could contain client identifiers, account numbers, or personal data.
4. **No secrets in code.** Use AWS Secrets Manager. Pre-commit hook blocks commits matching secret patterns.
5. **All model calls go through `_shared/llm.py`.** This wrapper handles retries, cost tracking, prompt versioning, and audit. Direct `boto3` calls to Bedrock are forbidden in agent code.
6. **All inter-agent calls use Pydantic schemas.** No untyped JSON. Schema mismatches must fail loudly at boundary.
7. **No agent stores state in memory.** State goes to AgentCore Memory, PostgreSQL, or S3. Agents are stateless and replayable.
8. **Compliance Agent has veto power.** If Compliance returns `BLOCK`, Orchestrator MUST surface the block to the user and halt the workflow. Cannot be bypassed.
9. **Pre-trade compliance is mandatory before any trade proposal reaches the UI.** Trade Agent MUST call Compliance Agent before returning a proposal.
10. **All financial calculations use `Decimal`, never `float`.** Floating-point errors compound disastrously in money math. There is a hook that flags `float` literals near keywords like `price`, `quantity`, `notional`.
11. **Every agent has a kill switch.** A row in `feature_flags` table can disable any agent globally. Orchestrator checks flags before routing.
12. **No regulated advice.** Outputs framed as analysis and recommendations to the user, who is the licensed professional. Never use phrases like "you should buy" or "I recommend buying" — use "the analysis indicates" or "the model output suggests."

---

## 7. Agent design contract

Every agent follows this contract. No exceptions.

### Required structure per agent

```
agents/<name>/
├── __init__.py
├── agent.py                # Main agent class
├── prompts/
│   ├── system.md           # System prompt (versioned via filename)
│   └── few_shot.md         # Few-shot examples
├── schemas.py              # Input/output Pydantic models (re-exported from _shared/schemas)
├── tools.py                # MCP tool registrations specific to this agent
├── evals/
│   ├── golden.jsonl        # Golden dataset (input → expected output)
│   └── eval.py             # Eval harness for THIS agent
├── README.md               # Purpose, I/O contract, SLOs, owner
└── test_<name>_agent.py    # Unit + property tests
```

### Required interface

```python
from _shared.base_agent import BaseAgent
from _shared.schemas.research import ResearchInput, ResearchOutput

class ResearchAgent(BaseAgent[ResearchInput, ResearchOutput]):
    name = "research"
    model = "claude-opus-4-7"  # Or read from config
    sla_p50_seconds = 8
    sla_p99_seconds = 30

    async def run(self, input: ResearchInput) -> ResearchOutput:
        ...
```

`BaseAgent` (in `_shared/base_agent.py`) handles audit logging, memory access, guardrails, retries, kill switch, and emits OTel spans. Agent authors implement `run()` only.

### Mandatory output fields (on every agent output)

Every output schema inherits from `AgentOutputBase`:
- `request_id: str`
- `agent_name: str`
- `model_name: str`
- `model_version: str`
- `prompt_version: str`
- `confidence: Literal["low", "medium", "high"]`
- `sources: list[Source]` — every claim must trace to a source
- `caveats: list[str]` — known limitations of this output
- `as_of: datetime` — data snapshot timestamp
- `cost_usd: Decimal` — model + tool cost for this call
- `duration_ms: int`

If an output has numbers (prices, returns, ratios), they go in a typed `numbers: dict[str, Decimal]` field, never as free text in summaries.

---

## 8. Data contracts (canonical schemas)

All Pydantic schemas live in `_shared/schemas/`. The frontend mirrors these in `frontend/lib/schemas/` using zod. **Schemas are the source of truth.** When schemas change, generate TS types via `datamodel-codegen`. This is automated by `make schemas`.

Core schema files:
- `portfolio.py` — Portfolio, Position, Holding, Lot, Cash
- `instrument.py` — Equity, Bond, ETF, Option (extensible)
- `market_data.py` — Quote, Bar, Fundamental, EarningsEvent
- `research.py` — Thesis, BullCase, BearCase, Catalyst, Source
- `risk.py` — FactorExposure, VaR, ScenarioResult, StressTest
- `compliance.py` — Mandate, Limit, Violation, RestrictedListEntry
- `trade.py` — TradeProposal, OrderTicket, ExecutionReport
- `events.py` — NewsItem, FilingEvent, InsiderTransaction
- `audit.py` — AuditRecord (immutable)

**Money is always `Decimal`.** Use `from decimal import Decimal` everywhere. Pydantic config: `model_config = ConfigDict(arbitrary_types_allowed=False, strict=True)`.

---

## 9. How to use Seeking Alpha (legally and well)

SA does not have a documented public API for redistribution. Approach:

1. **Subscriber-authenticated access only.** The user provides their SA Premium/Pro credentials, stored in AWS Secrets Manager. We act on their behalf as their tooling.
2. **Respect ToS and rate limits.** No scraping at scale. The MCP server `mcp_servers/seeking_alpha/` enforces a polite rate limit (default: 30 requests/minute) and respects `robots.txt`.
3. **Cache aggressively.** Article content is immutable once published; cache in S3 with 30-day TTL. Quant Ratings refresh daily; cache 24h.
4. **Cite, don't reproduce.** Research Agent NEVER reproduces SA articles verbatim. It paraphrases, attributes, and links. Quote rules: max 15 words per quote, max one quote per article. This rule is enforced by a guardrail in `_shared/guardrails.py::quote_compliance()`.
5. **Treat SA as one input among many.** Every Research output cross-references at least: SA articles, the company's filings, and consensus estimates. Avoid SA-only theses.
6. **Track author quality.** Persist `seeking_alpha_authors` table with track record metadata. Research Agent weights authors by realized performance, not click counts.

---

## 10. Testing strategy

- **Unit tests** for pure functions (calculations, transformations, schema validation). Target 90%+ coverage on `_shared/` and any module containing math.
- **Property tests** with Hypothesis for risk/portfolio math. Test invariants like "portfolio weights sum to 1", "VaR is non-negative", "correlation matrix is positive semi-definite".
- **Agent contract tests** — for each agent, run a fixed set of inputs and assert the output schema is valid and required fields are populated.
- **Golden dataset evals** — `evals/runners/run_all.py`. Each agent has a golden dataset; the runner reports per-agent metrics. Run nightly in CI; block merges that regress.
- **Integration tests** — spin up local stack (Postgres, OpenSearch, MinIO for S3) via Docker Compose. Test agent-to-agent flows.
- **End-to-end tests** — Playwright tests against a deployed dev environment. Test the three highest-value PM workflows: research-to-trade, daily-risk-check, weekly-IC-prep.

**Run before every PR:**
```bash
make check    # ruff + biome + mypy + pytest unit + biome lint
make eval-fast    # smoke evals on each agent (~5 min)
```

**Block merges if:**
- Coverage drops below 80% on changed files
- Any agent's eval score regresses by more than 3 percentage points
- Any compliance/audit/redaction test fails

---

## 11. Workflow with Claude Code

When working on this project, follow this loop:

1. **Read first.** Before writing code, read `docs/architecture.md`, the relevant `docs/agents/<name>.md`, and the existing module if you're modifying. Use `view` not `cat`.
2. **Plan in writing.** For any task touching 3+ files, write the plan first as a markdown checklist. I prefer plan mode (Shift+Tab) for these.
3. **Schemas first, then logic.** Pydantic models before implementation. The schema is the contract; once the contract is right, implementation falls out.
4. **Write tests with the code, not after.** TDD on math-heavy functions; concurrent test+impl on integration code.
5. **Small, focused commits.** Conventional Commits (`feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `chore:`). Reference the agent: `feat(research): add author quality weighting`.
6. **Run `make check` before reporting done.** Don't claim a task is complete until checks pass locally.
7. **Update CLAUDE.md when you learn something.** If a mistake reveals a missing rule, propose the addition.

### When in doubt
- **Unclear requirements:** ask, don't guess. Especially on financial logic.
- **Stuck after two attempts:** stop, summarize, ask. Don't spiral.
- **Tempted to skip a guardrail "just for testing":** don't. Guardrails are part of the system.

### What NOT to do
- Don't introduce new dependencies without justification in commit message.
- Don't refactor adjacent unrelated code in a feature PR.
- Don't disable failing tests. Fix them or, if intentional, document and ticket.
- Don't add comments explaining what code does. Comments explain *why*, not *what*.
- Don't write speculative abstractions. YAGNI hard. Prefer duplication over premature abstraction.

---

## 12. Cost discipline

LLM cost is a real budget line. Be deliberate:

- Use the cheapest model that meets accuracy. Sentiment scoring on Haiku, not Opus.
- Cache aggressively. Identical input → cached output for 24h on read-mostly agents.
- Use prompt caching (Bedrock's caching feature) for system prompts and few-shot blocks.
- Batch where possible. Sentiment scoring 100 articles in one call beats 100 individual calls.
- Stream when responses are long enough that first-token latency matters; otherwise non-streaming.
- Track cost per agent invocation in audit log. Dashboard alerts if any agent exceeds budget.

---

## 13. Compliance and regulation (read this seriously)

This is a tool for a licensed professional. The user is the fiduciary. The platform is decision support, not advisor. But several rules apply regardless:

- **SEC Rule 17a-4** (record retention): all communications and outputs retained for 7 years, immutable. Audit log handles this.
- **GDPR / CCPA**: client PII handled per `docs/compliance.md`. Right-to-be-forgotten implemented at the data layer; agent outputs about a forgotten client are also purged.
- **Marketing rule (SEC 206(4)-1)**: any performance numbers shown have GIPS-style disclosures. Reporting Agent enforces this.
- **Best execution**: Trade Agent records the rationale for any order routing decision.
- **Books and records**: every PM decision and the supporting analysis is queryable by date, ticker, account, or user.

If a feature touches compliance, the spec must reference the rule, the implementation must include the rule ID in code comments, and the test suite must include a regression test named after the rule.

---

## 14. Definitions and glossary

- **Agent**: a specialized LLM-driven service with one job and a typed I/O contract.
- **Orchestrator**: the agent that talks to the user and routes to specialists.
- **Mandate**: a set of investment constraints (e.g., "no tobacco, max 5% in any one position").
- **IPS**: Investment Policy Statement.
- **VaR**: Value at Risk.
- **Attribution**: decomposition of returns into sources (sector, factor, security selection).
- **Brinson-Fachler**: a specific attribution methodology, the default in `risk_agent`.
- **Tracking error**: standard deviation of (portfolio return − benchmark return).
- **A2A**: Agent-to-Agent protocol.
- **MCP**: Model Context Protocol; how agents access tools.
- **AgentCore**: AWS Bedrock AgentCore; the runtime platform.
- **SA**: Seeking Alpha.

---

## 15. Roles and ownership

(Fill in as the team forms. Every agent has an owner. Every owner reviews PRs touching their agent.)

- Research Agent: TBD
- Risk Agent: TBD
- ...

---

## 16. Append-only learnings

When Claude Code makes a mistake worth not repeating, add a one-liner here.

- (none yet)
