# Architecture

This document is the canonical reference for how the system is built and why. ADRs (Architecture Decision Records) are appended at the bottom — never edited, only added to.

## System overview

A multi-agent platform where specialist agents (each one job, well-defined I/O) are coordinated by an orchestrator. The asset manager interacts only with the orchestrator. Agents communicate via A2A protocol; tools are accessed via MCP through AgentCore Gateway.

## Core principles

1. **Stateless agents.** State lives in AgentCore Memory, PostgreSQL, or S3. Agents are replayable from inputs.
2. **Typed contracts.** Every agent boundary is a Pydantic schema. No untyped JSON.
3. **Audit everything.** Every output is logged with full provenance. Append-only, immutable.
4. **Human-in-the-loop on money.** No autonomous trade execution.
5. **Compliance has veto power.** Compliance Agent's BLOCK halts the workflow.
6. **Defense in depth.** Hooks (Claude Code), guardrails (runtime), and CI checks all enforce the critical rules.

## Layered architecture

### Layer 1 — Frontend (Next.js)

- App Router, Server Components by default
- Tailwind + shadcn/ui for design system
- TanStack Query for server state
- Zod for runtime validation (mirrors Pydantic schemas)
- Auth via Cognito + Okta SAML
- Three primary surfaces:
  - **Conversation surface**: chat with the Orchestrator. Agent outputs render as structured cards (see `Individual_agents.pdf` reference layout).
  - **Portfolio surface**: holdings, performance, attribution, risk dashboards.
  - **Approval surface**: trade proposals, compliance flags, blocking issues, all requiring explicit approval.

### Layer 2 — Orchestrator

- Single point of contact for the user.
- Routes requests to specialist agents based on intent classification.
- Maintains conversation memory (AgentCore Memory).
- Aggregates multi-agent responses into coherent answers.
- Enforces compliance veto path.
- Surfaces approval prompts for any action affecting the portfolio.

Routing is done via a small classifier model (Haiku) producing `{intent, agents_to_invoke, parallelization_strategy}`. Orchestrator then dispatches.

### Layer 3 — Specialist agents

Each agent is a separate AgentCore Runtime deployment. See per-agent docs in `docs/agents/`.

Inter-agent communication uses A2A protocol. Direct HTTP calls allowed for simple synchronous request/response within trusted boundaries; A2A used for richer multi-turn coordination.

Some workflows fan out (Orchestrator invokes Research, Quant, and Risk in parallel for a deep-dive on a name). Some are sequential (Trade Agent must call Compliance before returning).

### Layer 4 — Shared services

- **Memory**: AgentCore Memory for conversation state, cross-session learnings, user preferences.
- **Vector store**: OpenSearch for semantic search over SA articles, filings, transcripts, internal research.
- **Audit log**: DynamoDB (hot) + S3 Glacier (cold). Every agent invocation, every tool call, every model call.
- **Feature flags**: simple PostgreSQL table; Orchestrator checks before invoking any agent.
- **Guardrails**: `_shared/guardrails.py` — input validation, output validation, content filtering, quote-compliance, PII redaction.
- **Eval harness**: `evals/` — runs nightly in CI, on every merge, and on demand via `/eval`.

### Layer 5 — Tool layer (MCP servers)

Each external integration is an MCP server. AgentCore Gateway exposes them to agents with auth, rate limiting, and audit.

- `seeking_alpha`: SA Premium/Pro authenticated access. Article search, Quant Ratings, transcripts, author metadata. Rate-limited.
- `market_data`: prices, fundamentals, FX. Provider TBD (Polygon, IEX Cloud, or institutional like Bloomberg/Refinitiv).
- `custodian`: portfolio holdings, cash, transactions. Per-custodian adapters (Schwab, Fidelity, IBKR, etc.).
- `filings`: SEC EDGAR. Filings, insider transactions.
- `risk_engine`: factor models, optimization, scenario analysis. v1 uses Riskfolio-Lib; v2 may integrate Axioma.
- `news`: news aggregator (Benzinga, NewsAPI, or similar).
- `oms`: order management system. Read-only by default; writes only via human-approved trade tickets.

### Layer 6 — Data layer

- **PostgreSQL** (relational): users, mandates, portfolios, positions, transactions, audit metadata, feature flags.
- **TimescaleDB** (extension): time-series prices, returns, NAV history.
- **OpenSearch**: vector + BM25 hybrid search over text content.
- **S3**: raw documents (filings, transcripts, articles), portfolio snapshots, eval reports.
- **DynamoDB**: hot audit log.
- **Secrets Manager**: credentials, API keys.

Daily portfolio snapshots are immutable: every day's holdings, cash, and computed metrics are a separate S3 object, keyed by date. This is what makes "as_of" queries work.

## Sequence: research-to-trade flow

```
User: "Take a deep look at NVDA — should I be adjusting my position?"
  ↓
Orchestrator (intent: deep-dive + position-review)
  ↓
Parallel fan-out:
  - Research Agent → thesis (uses SA + filings + news)
  - Quant Agent → factor scores, screening rank
  - Risk Agent → exposure if position were doubled, halved, eliminated
  - Earnings Agent → most recent call analysis
  - News Agent → recent events
  ↓
Orchestrator aggregates → coherent narrative
  ↓
User: "Reduce by half"
  ↓
Trade Agent → proposed order
  ↓
Compliance Agent → checks mandate, restricted lists, position limits
  ↓
If BLOCK → surfaced to user, workflow halts
If PASS → proposal returned to UI for approval
  ↓
User clicks Approve → OMS receives order via custodian MCP
  ↓
Audit log updated at every step
```

## Failure modes and resilience

- **Agent timeout**: Orchestrator has per-agent timeouts (default 30s, configurable). Timed-out agents return partial results with `caveats=["agent_timeout"]`.
- **Tool failure**: agent returns degraded output, never silent failure. `caveats` lists the failure.
- **Compliance Agent down**: trade workflow halts. We do NOT default-allow on Compliance failure.
- **LLM failure**: retry with exponential backoff (3 attempts), then return error. Cost tracked even on failure.
- **Cost runaway**: per-agent and per-user daily cost limits. Orchestrator refuses to invoke if limits exceeded.

## Environments

- **dev**: local stack (Docker Compose: Postgres, OpenSearch, MinIO). Bedrock calls go to AWS dev account. Synthetic portfolio data.
- **staging**: full AWS deployment. Mirror of prod. Real SA test account, paper-trading custodian.
- **prod**: locked-down. Deployment via CI only. Manual approval gate before prod deploy.

## ADRs (append-only)

### ADR-001: Choose AgentCore over self-built orchestration
**Status**: Accepted  
**Date**: TBD  
**Context**: Need production multi-agent platform. Options: build on Lambda + Step Functions, use LangGraph alone, or AgentCore.  
**Decision**: AgentCore. Reasons: managed runtime, A2A and MCP support, built-in memory, observability, evaluations. Reduces bespoke infra significantly.  
**Consequences**: AWS-coupled. If we ever multi-cloud, A2A and MCP keep agents portable but the runtime must be redone.

### ADR-002: Pydantic v2 with strict mode for all agent I/O
**Status**: Accepted  
**Date**: TBD  
**Context**: Agent boundaries can leak with untyped JSON, especially when LLMs produce sloppy output.  
**Decision**: Pydantic v2, strict=True, extra=forbid on every agent input and output.  
**Consequences**: Schema changes are breaking. Migrations need versioning. Worth it for correctness.

### ADR-003: Decimal for all money math
**Status**: Accepted  
**Date**: TBD  
**Context**: Floats accumulate error and create silent bugs in P&L.  
**Decision**: `decimal.Decimal` everywhere, banker's rounding, 28 digits of precision.  
**Consequences**: Slightly more verbose code. Type-coercion at numpy boundaries needed for risk math.

### ADR-004: Compliance Agent has veto power
**Status**: Accepted  
**Date**: TBD  
**Context**: Need a hard stop on trades violating mandates or restricted lists.  
**Decision**: Compliance Agent BLOCK halts workflow at Orchestrator level. Cannot be bypassed without admin override and audit entry.  
**Consequences**: Must guarantee Compliance is highly available. Outages block trading. Acceptable trade-off; alternative is unsafe.

### ADR-005: Treat Seeking Alpha as a content source, not a system of record
**Status**: Accepted  
**Date**: TBD  
**Context**: SA is strong on theses and transcripts but missing portfolio-level features. Tempting to build the whole UX around it; this would lock us in and miss the bigger opportunity.  
**Decision**: SA is one input among several. Research Agent uses SA but cross-references filings, news, and consensus. Risk, attribution, compliance, execution are all built independently.  
**Consequences**: Less SA-shaped UX. Better long-term flexibility. Aligns with the gap analysis.
