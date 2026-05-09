---
name: financial-math
description: Rules for performing financial calculations correctly. Apply whenever code computes prices, returns, weights, exposures, NAV, P&L, attribution, risk metrics, or any other monetary or numerical financial quantity. Triggers on keywords: price, return, NAV, P&L, PnL, weight, exposure, VaR, volatility, Sharpe, attribution, factor, beta, correlation, covariance, optimization, portfolio math, money, currency, decimal.
---

# Financial math skill

This is the most error-prone area of the codebase. Financial bugs are silent until they hit a client report or a P&L statement. Read carefully.

## Rule 1: Money is Decimal

Use `decimal.Decimal` for ALL monetary values, prices, and quantities. Never float, never int (except share counts when integer-only is enforced).

```python
from decimal import Decimal, ROUND_HALF_EVEN, getcontext

# Set context once in _shared/decimal_context.py
getcontext().prec = 28
getcontext().rounding = ROUND_HALF_EVEN  # banker's rounding

# Right
price = Decimal("123.45")
nav = Decimal("1000000.00")

# Wrong
price = 123.45             # float!
nav = float(input_str)     # float!
```

When parsing from external sources (which give you strings or floats), cast immediately at the boundary:

```python
def parse_price(raw: str | float | int) -> Decimal:
    return Decimal(str(raw))   # str(raw) avoids float-binary surprises
```

## Rule 2: Returns and percentages

Returns are dimensionless. Use `Decimal` for percentage points but be explicit about units in variable names.

```python
# Right
return_pct: Decimal = Decimal("0.0523")              # 5.23% as a fraction
return_bps: Decimal = Decimal("523")                 # in basis points

# Wrong
return: float = 0.0523                                # float
ret = 5.23                                            # what unit? %? bps?
```

Naming convention: `_pct` for fractions (0.0523), `_bps` for basis points (523), `_pcts` for "human-readable percent" (5.23). Always state which.

## Rule 3: Time-weighted vs money-weighted returns

These produce different numbers and answer different questions:

- **TWR** (time-weighted return): for benchmarking manager skill. Excludes effect of cash flows.
- **MWR/IRR** (money-weighted/internal rate of return): for what the client experienced. Includes cash flow timing.

Use the right one. Reporting Agent must label which is shown. GIPS performance presentation uses TWR.

## Rule 4: Compounding

```python
from decimal import Decimal

# Compound monthly returns to get annual return
def compound_returns(monthly_returns: list[Decimal]) -> Decimal:
    """Returns are fractions, e.g. 0.01 for 1%."""
    result = Decimal("1")
    for r in monthly_returns:
        result *= (Decimal("1") + r)
    return result - Decimal("1")
```

For annualization from N periods: `(1 + total_return) ** (periods_per_year / N) - 1`. Use `Decimal` exponentiation via `**` with `Decimal` only — mixing types raises in strict mode.

## Rule 5: Portfolio math

Weights MUST sum to 1 (or to 1 + cash_weight if you separate cash). Always assert this with a tolerance:

```python
def assert_weights_sum_to_one(weights: dict[str, Decimal], tolerance: Decimal = Decimal("0.0001")) -> None:
    total = sum(weights.values(), Decimal("0"))
    if abs(total - Decimal("1")) > tolerance:
        raise ValueError(f"Weights sum to {total}, expected 1.0 ± {tolerance}")
```

## Rule 6: Risk metrics

**VaR**: report the methodology (historical, parametric, Monte Carlo), confidence level, and horizon. e.g. `var_95_1d_historical`. Never just "VaR".

**Volatility**: annualized by default; if not annualized, name says so (e.g. `vol_daily`). Annualize daily returns by `* sqrt(252)`, weekly by `* sqrt(52)`, monthly by `* sqrt(12)`. Use trading days for daily.

**Sharpe**: `(annual_return - rf) / annual_vol`. State the risk-free rate used and its source (e.g., 3-month T-bill, FRED DGS3MO).

**Beta**: `cov(asset, benchmark) / var(benchmark)`. State the benchmark explicitly.

**Correlation matrices**: must be positive semi-definite. After construction or shrinkage, validate. Property test:

```python
import numpy as np
from hypothesis import given, strategies as st

def is_psd(matrix: np.ndarray, tol: float = 1e-8) -> bool:
    eigenvalues = np.linalg.eigvalsh(matrix)
    return bool(np.all(eigenvalues >= -tol))
```

(This is one place where `numpy` floats are okay — eigenvalue computation. The output of risk math gets cast back to Decimal at the schema boundary.)

## Rule 7: Currency

If the platform handles non-USD assets, every price has a currency. NEVER mix currencies in arithmetic without converting:

```python
class Money(BaseModel):
    amount: Decimal
    currency: Literal["USD", "EUR", "GBP", "JPY", "CAD", "AUD", "CHF"]

def add_money(a: Money, b: Money, fx: FxQuote) -> Money:
    if a.currency == b.currency:
        return Money(amount=a.amount + b.amount, currency=a.currency)
    # else convert b to a's currency using fx, with explicit rate timestamp
```

Never silently coerce. FX conversion is an explicit operation with a rate, timestamp, and source.

## Rule 8: Attribution

Brinson-Fachler decomposes return into allocation, selection, and interaction effects. The components must sum to the total active return (within a small tolerance from rounding). Test this invariant.

Sector attribution: needs sector mapping for both portfolio and benchmark, both as of the same date. Use GICS by default.

## Rule 9: Tax lots

Lot accounting is its own special discipline:
- **Lot identification methods**: FIFO, LIFO, HIFO, Specific ID, Average Cost. The user picks; default FIFO.
- **Wash sale rules**: 30 days before and after a sale at a loss; the loss is disallowed and added to basis of the replacement.
- **Long-term vs short-term**: holding period > 1 year for long-term capital gains in US.

Never compute taxes without accounting for holding period and wash sales. If unsure, return partial output and flag in `caveats`.

## Rule 10: Test the invariants

Property tests with Hypothesis are mandatory for any function in `_shared/financial.py` and any agent that does math. Examples:

```python
from hypothesis import given, strategies as st
from decimal import Decimal

decimal_returns = st.decimals(min_value=Decimal("-0.5"), max_value=Decimal("0.5"), places=6, allow_nan=False, allow_infinity=False)

@given(st.lists(decimal_returns, min_size=1, max_size=120))
def test_compounded_return_consistent_with_geometric(returns):
    compounded = compound_returns(returns)
    # geometric mean of (1 + r) ** (1/n) gives same result when annualized to n periods
    ...

@given(st.lists(decimal_returns, min_size=2, max_size=12))
def test_total_return_unaffected_by_zero_returns(returns):
    augmented = returns + [Decimal("0")] * 5
    assert compound_returns(returns) == compound_returns(augmented)
```

## Common mistakes

- ❌ `0.1 + 0.2 == 0.3` is False with floats. `Decimal("0.1") + Decimal("0.2") == Decimal("0.3")` is True.
- ❌ Annualizing a 30-day return by `* 12` instead of `(1 + r) ** (365/30) - 1`.
- ❌ Using `np.std` (population std) when you want sample std for volatility. `ddof=1`.
- ❌ Forgetting that benchmark beta is by definition 1.0; if your math gives 1.0001, that's rounding, but if it gives 0.97, your math is wrong.
- ❌ Computing portfolio-level VaR by averaging position VaRs. VaR doesn't aggregate that way; you need the joint distribution.
- ❌ Reporting performance after fees if the audience expects gross of fees, or vice versa. State which.
