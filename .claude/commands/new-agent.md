---
description: Scaffold a new agent following the project contract
allowed-tools: Read, Write, Edit, Bash
---

# Create a new agent

You are creating a new agent in this multi-agent asset management platform. Follow the contract in CLAUDE.md section 7 EXACTLY.

The agent name is: $ARGUMENTS

## Steps

1. **Confirm the agent name and purpose with me before creating files** — repeat back what you understood, list the inputs/outputs at a high level, and ask me to confirm.

2. After confirmation, create this directory structure under `agents/<name>/`:
   - `__init__.py`
   - `agent.py` — class inheriting `BaseAgent[InputModel, OutputModel]`
   - `prompts/system.md` — system prompt with version comment at top (`<!-- version: 1.0.0 -->`)
   - `prompts/few_shot.md` — at least 3 few-shot examples
   - `schemas.py` — re-export from `_shared.schemas.<name>`
   - `tools.py` — MCP tool registrations specific to this agent
   - `evals/golden.jsonl` — placeholder with 5 example rows
   - `evals/eval.py` — agent-specific eval harness
   - `README.md` — purpose, I/O contract, SLOs, owner (TBD), kill-switch flag name
   - `test_<name>_agent.py` — at minimum: schema test, kill-switch test, one happy-path test

3. Add input/output schemas to `_shared/schemas/<name>.py`. Inherit output from `AgentOutputBase` (CLAUDE.md section 7).

4. Register the agent in `agents/orchestrator/registry.py`. Add to the routing table with a one-line description.

5. Add a feature flag entry to `infra/stacks/data_stack.py` for the kill switch (default: enabled in dev, disabled in prod until promoted).

6. Run `make schemas` to regenerate TS types, then `make check` to verify.

## Rules

- The agent class MUST inherit from `BaseAgent`.
- The `run()` method MUST have `@audited` decorator.
- Output MUST include all `AgentOutputBase` fields.
- All money MUST use `Decimal`.
- Costs MUST be propagated from the LLM call to the output.
- The agent README MUST state SLA targets (p50, p99 latency) and accuracy target on the golden dataset.

If anything in CLAUDE.md is unclear or seems inconsistent for this agent, ask me before improvising.
