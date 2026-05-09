# Data contracts

The canonical reference for every Pydantic schema. The frontend mirrors these in zod via `make schemas`.

> **Rule**: schemas are the source of truth. When schemas change, regenerate TS types, update consumers, run consumer tests.

## Conventions

- All models inherit from a `StrictModel` base with `ConfigDict(strict=True, extra="forbid", arbitrary_types_allowed=False)`.
- Money is `Decimal` (string-serialized in JSON: `"123.45"`).
- Datetimes are timezone-aware, UTC, ISO-8601.
- IDs are UUIDs unless tied to an external system (then namespaced: `"sa:article:12345"`, `"sec:filing:0001..."`).
- Currencies are 3-letter ISO codes.
- Tickers are uppercase + exchange suffix when ambiguous (`"BRK.B"`, `"7203.T"`).

## Base schemas (`_shared/schemas/base.py`)

```python
from __future__ import annotations
from datetime import datetime
from decimal import Decimal
from typing import Literal
from uuid import UUID
from pydantic import BaseModel, ConfigDict, Field

class StrictModel(BaseModel):
    model_config = ConfigDict(strict=True, extra="forbid", arbitrary_types_allowed=False)

class Source(StrictModel):
    kind: Literal["seeking_alpha", "sec_filing", "news", "transcript", "internal", "market_data", "consensus"]
    id: str
    title: str | None = None
    url: str | None = None
    author: str | None = None
    published_at: datetime | None = None
    excerpt: str | None = Field(default=None, max_length=200)

class AgentOutputBase(StrictModel):
    request_id: UUID
    agent_name: str
    model_name: str
    model_version: str
    prompt_version: str
    confidence: Literal["low", "medium", "high"]
    sources: list[Source] = Field(default_factory=list)
    caveats: list[str] = Field(default_factory=list)
    as_of: datetime
    cost_usd: Decimal
    duration_ms: int
    clarification_needed: bool = False
    clarification_question: str | None = None
```

## Instrument (`_shared/schemas/instrument.py`)

```python
from typing import Literal

AssetClass = Literal["equity", "etf", "bond", "option", "future", "fx", "crypto", "cash"]

class Instrument(StrictModel):
    instrument_id: str           # canonical id, e.g. CUSIP or internal
    ticker: str
    asset_class: AssetClass
    currency: str                # ISO-3
    name: str
    sector: str | None = None    # GICS Sector
    industry: str | None = None  # GICS Industry
    country: str | None = None   # ISO-2
    exchange: str | None = None
```

## Portfolio (`_shared/schemas/portfolio.py`)

```python
class Lot(StrictModel):
    lot_id: UUID
    acquired_at: datetime
    quantity: Decimal
    cost_basis_per_share: Decimal
    cost_basis_total: Decimal       # validated == quantity * cost_basis_per_share

class Position(StrictModel):
    instrument: Instrument
    quantity: Decimal
    market_price: Decimal
    market_value: Decimal            # quantity * market_price
    cost_basis_total: Decimal
    unrealized_pnl: Decimal
    weight: Decimal                  # of NAV
    lots: list[Lot] = Field(default_factory=list)

class CashBalance(StrictModel):
    currency: str
    amount: Decimal

class Portfolio(StrictModel):
    portfolio_id: UUID
    name: str
    base_currency: str
    as_of: datetime
    nav: Decimal
    positions: list[Position]
    cash: list[CashBalance]
    benchmark: str | None = None     # e.g. "SPX", "ACWI"
    mandate_id: UUID | None = None
```

## Research (`_shared/schemas/research.py`)

```python
class Catalyst(StrictModel):
    description: str
    expected_at: datetime | None = None
    impact: Literal["small", "moderate", "large"]
    confidence: Literal["low", "medium", "high"]

class ThesisPoint(StrictModel):
    point: str
    evidence: list[Source]
    counterpoint: str | None = None
    testable: bool                    # can this be verified from data?

class ValuationSummary(StrictModel):
    method: Literal["dcf", "multiples", "sotp", "asset_based", "blended"]
    fair_value_per_share: Decimal
    fair_value_currency: str
    upside_pct: Decimal
    key_assumptions: list[str]

class ResearchInput(StrictModel):
    ticker: str
    user_id: UUID
    question: str | None = None       # optional specific question
    depth: Literal["quick", "standard", "deep"] = "standard"

class ResearchOutput(AgentOutputBase):
    ticker: str
    company_name: str
    one_line_summary: str
    bull_case: list[ThesisPoint]
    bear_case: list[ThesisPoint]
    catalysts: list[Catalyst]
    valuation: ValuationSummary | None = None
    sa_author_consensus: Literal["bullish", "neutral", "bearish", "mixed"] | None = None
    numbers: dict[str, Decimal] = Field(default_factory=dict)
```

## Risk (`_shared/schemas/risk.py`)

```python
class FactorExposure(StrictModel):
    factor: str                       # e.g. "value", "momentum", "quality"
    model: str                        # e.g. "fama_french_5"
    exposure: Decimal                 # standardized exposure
    contribution_to_risk_pct: Decimal

class VaRResult(StrictModel):
    methodology: Literal["historical", "parametric", "monte_carlo"]
    confidence: Decimal               # e.g. 0.95
    horizon_days: int                 # e.g. 1
    var_amount: Decimal               # in base currency
    var_pct: Decimal                  # of NAV
    cvar_amount: Decimal | None = None

class ScenarioResult(StrictModel):
    scenario: str                     # e.g. "rates_+100bps", "spx_-20pct"
    pnl_impact: Decimal
    pnl_impact_pct: Decimal
    most_affected_positions: list[str]

class RiskInput(StrictModel):
    portfolio_id: UUID
    as_of: datetime | None = None     # default: now
    factor_model: str = "fama_french_5"
    var_confidence: Decimal = Decimal("0.95")
    scenarios: list[str] = Field(default_factory=list)

class RiskOutput(AgentOutputBase):
    portfolio_id: UUID
    nav: Decimal
    factor_exposures: list[FactorExposure]
    sector_concentrations: dict[str, Decimal]   # GICS sector → weight
    top_concentrations: list[tuple[str, Decimal]]  # (ticker, weight) top 10
    var: VaRResult
    tracking_error_annual_pct: Decimal | None = None
    beta_to_benchmark: Decimal | None = None
    scenarios: list[ScenarioResult] = Field(default_factory=list)
    numbers: dict[str, Decimal] = Field(default_factory=dict)
```

## Trade (`_shared/schemas/trade.py`)

```python
class TradeProposal(StrictModel):
    proposal_id: UUID
    portfolio_id: UUID
    instrument: Instrument
    side: Literal["buy", "sell"]
    quantity: Decimal
    order_type: Literal["market", "limit"]
    limit_price: Decimal | None = None
    rationale: str
    expected_impact: dict[str, Decimal]       # e.g. {"weight_after": 0.05, "factor_value_after": 0.3}
    pre_trade_check_id: UUID                   # references compliance check

class ComplianceResult(StrictModel):
    decision: Literal["pass", "warn", "block"]
    rules_evaluated: list[str]
    violations: list[str]
    warnings: list[str]

class TradeInput(StrictModel):
    portfolio_id: UUID
    intent: str                                 # e.g. "reduce NVDA by half"
    user_id: UUID

class TradeOutput(AgentOutputBase):
    proposals: list[TradeProposal]
    compliance: ComplianceResult
    requires_approval: Literal[True] = True     # always True; never bypass
```

## Compliance (`_shared/schemas/compliance.py`)

```python
class Mandate(StrictModel):
    mandate_id: UUID
    name: str
    portfolio_ids: list[UUID]
    rules: list[Rule]

class Rule(StrictModel):
    rule_id: str
    description: str
    type: Literal["concentration", "sector_limit", "restricted_list", "esg", "leverage", "custom"]
    parameters: dict[str, str | Decimal | int | bool]

class Violation(StrictModel):
    rule_id: str
    severity: Literal["info", "warn", "block"]
    description: str
    affected_positions: list[str]
    suggested_remedy: str | None = None

class ComplianceInput(StrictModel):
    portfolio_id: UUID
    proposed_trades: list[TradeProposal] = Field(default_factory=list)
    check_type: Literal["pre_trade", "post_trade", "monitoring"]

class ComplianceOutput(AgentOutputBase):
    portfolio_id: UUID
    decision: Literal["pass", "warn", "block"]
    violations: list[Violation] = Field(default_factory=list)
    rules_evaluated: int
```

## Audit (`_shared/schemas/audit.py`)

```python
class AuditRecord(StrictModel):
    """Immutable. Append-only. SEC 17a-4 compliant retention."""
    record_id: UUID
    timestamp: datetime
    user_id: UUID | None
    agent_name: str
    request_id: UUID
    input_redacted: dict
    output_redacted: dict
    model_name: str
    model_version: str
    prompt_version: str
    cost_usd: Decimal
    duration_ms: int
    tools_called: list[str]
    parent_request_id: UUID | None = None         # for chained agent calls
    decision: Literal["completed", "failed", "blocked", "timeout"]
    error: str | None = None
```

## TypeScript mirroring

Run `make schemas` to regenerate. The script `scripts/generate_ts_schemas.py` reads all Pydantic models in `_shared/schemas/` and emits zod schemas + TS types in `frontend/lib/schemas/`. The frontend imports these and validates every API response.

```typescript
import { ResearchOutputSchema, type ResearchOutput } from "@/lib/schemas/research";

const data = ResearchOutputSchema.parse(await response.json()); // throws on schema mismatch
```
