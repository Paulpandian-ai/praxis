---
description: Run evals for one or all agents and produce a comparison report
allowed-tools: Read, Bash, Write
---

# Run agent evaluations

Target: $ARGUMENTS (an agent name, or `all` for all agents)

## Steps

1. Verify `evals/datasets/<agent>/golden.jsonl` exists (or all goldens for `all`).
2. Run `python -m evals.runners.run_agent --agent $ARGUMENTS --output evals/reports/`.
3. Read the latest report under `evals/reports/`.
4. Compare against the previous report. Highlight:
   - Pass-rate changes (>3 percentage points)
   - Cost changes (>20%)
   - Latency p99 changes (>30%)
   - Schema-validation failures (any number is concerning)
5. Output a markdown summary for each agent: pass rate, p50/p99 latency, total cost, top 3 failures with example inputs.
6. If any agent regresses by >3 percentage points, list the failed cases and propose hypotheses.

Do NOT propose changes to the agent code in this session — eval and analyze only. Code changes happen in a separate session against a clear hypothesis.
