---
description: Audit recent changes for compliance with critical rules in CLAUDE.md section 6
allowed-tools: Read, Bash, Grep, Glob
---

# Compliance and safety audit

Run a full audit against the critical rules in CLAUDE.md section 6.

## Checks

1. **Trade execution gating.** `git grep -n "execute_order\|submit_order\|place_order"` — every call site must have `approval_required=True` in scope, or be in tests.
2. **@audited decorator.** Every `agents/*/agent.py` file's `run()` method must have `@audited`.
3. **Float-money.** `git grep -nE "(price|qty|amount|notional|cost|value|nav|return|pnl|cash|balance|fee|premium|coupon|principal)\s*:\s*float"` in agents/, mcp_servers/, data/, _shared/.
4. **Direct boto3 Bedrock.** `git grep -n "boto3.*bedrock\|bedrock-runtime"` outside `_shared/llm.py` is forbidden.
5. **Untyped agent I/O.** Search for `dict\[str, Any\]` in agent input/output signatures.
6. **PII in logs.** Search for log calls that include keywords like `client_name`, `account_number`, `ssn`, `email` not preceded by `redact(`.
7. **Compliance Agent veto path.** `git grep -n "BLOCK\|compliance_block"` — every block path must call `orchestrator.halt_workflow()`.
8. **Secrets in code.** Run the same patterns as `.claude/hooks/block_secrets.sh` on the entire repo.
9. **Quote compliance for SA content.** Search for SA article content rendered in any UI; verify `quote_compliance()` is called.
10. **Kill-switch coverage.** Every agent in `agents/orchestrator/registry.py` has a corresponding entry in `feature_flags`.

## Output

Produce a markdown report:

```markdown
# Compliance audit — <date>

## Summary
- Rules checked: 10
- Violations: N
- Warnings: M

## Violations
(detailed)

## Warnings
(detailed)

## Recommendations
(actionable items)
```

If any violations found, exit with a clear summary and STOP. Do not auto-fix — surface to me for review first.
