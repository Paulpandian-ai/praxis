#!/usr/bin/env bash
# Block use of `float` near financial keywords. Money math uses Decimal.
# This is a coarse-grained signal — false positives are okay; the cost of float in money is much higher.

set -euo pipefail

input=$(cat)
path=$(echo "$input" | jq -r '.tool_input.file_path // ""')
content=$(echo "$input" | jq -r '.tool_input.content // .tool_input.new_string // ""')

# Only apply to Python files in agent / financial code paths
case "$path" in
  *agents/*|*mcp_servers/*|*data/*|*_shared/*)
    ;;
  *)
    exit 0
    ;;
esac

# Skip test files
case "$path" in
  *test_*.py|*/tests/*) exit 0 ;;
esac

# Look for float annotations near money keywords
money_keywords='price|quantity|qty|amount|notional|cost|value|nav|aum|return|pnl|p_and_l|cash|balance|fee|premium|spread|yield|coupon|principal'

# Python-style: `price: float`, `def x(price: float)`, `price = 12.5` (with float context)
if echo "$content" | grep -qE "(${money_keywords})\s*:\s*float"; then
  match=$(echo "$content" | grep -nE "(${money_keywords})\s*:\s*float" | head -1)
  echo "{\"decision\": \"block\", \"reason\": \"Use Decimal for monetary values, not float, in $path. Found: $match. Import Decimal: from decimal import Decimal\"}"
  exit 0
fi

# Function arg type hints
if echo "$content" | grep -qE "def [a-zA-Z_]+\([^)]*\b(${money_keywords})\b[^)]*:\s*float"; then
  echo "{\"decision\": \"block\", \"reason\": \"Function argument typed as float for monetary value in $path. Use Decimal.\"}"
  exit 0
fi

exit 0
