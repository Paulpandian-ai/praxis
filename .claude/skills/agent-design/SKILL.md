---
name: agent-design
description: Guidelines for designing or modifying any specialist agent in this asset management platform. Apply whenever creating a new agent, modifying an existing agent's prompts, schemas, tools, or eval harness, or reviewing agent code. Triggers on: "agent", "research agent", "risk agent", "compliance agent", "orchestrator", "schema", "prompt", and any work in the agents/ directory.
---

# Agent design skill

This skill encodes how every agent in this platform is built. It is mandatory reading before touching anything in `agents/`.

## The agent contract (binding)

Every agent is a stateless service with:

1. **One job.** If you can't describe the agent's purpose in one sentence without "and", it's two agents.
2. **A typed input schema.** Pydantic model in `_shared/schemas/<agent>.py`.
3. **A typed output schema.** Pydantic model inheriting `AgentOutputBase`.
4. **A versioned system prompt.** Markdown file in `agents/<name>/prompts/system.md` with `<!-- version: x.y.z -->` at top.
5. **Few-shot examples.** At least 3, in `prompts/few_shot.md`.
6. **A golden eval dataset.** At least 20 cases in `evals/golden.jsonl`.
7. **An owner.** In the agent README.
8. **A kill switch.** Feature flag in `feature_flags` table. Orchestrator checks before invoking.
9. **Audit logging.** `@audited` decorator on `run()`.
10. **Documented SLAs.** p50 and p99 latency targets in README.

## Prompt design

System prompts follow this structure:

```markdown
<!-- version: 1.0.0 -->
# <Agent Name> Agent

## Role
You are the <agent name> agent for an asset management platform. Your single job is <one sentence>.

## Inputs
You will receive a <InputModel> JSON object with these fields: ...

## Outputs
You MUST return a <OutputModel> JSON object with these fields: ...
- All money values are Decimal strings (e.g. "123.45"), never floats.
- Every claim must have at least one source in the `sources` array.
- Set `confidence` based on: <criteria>.

## Rules
- Do NOT advise the user to take any specific action. Frame outputs as analysis.
- If the input is ambiguous, return `clarification_needed: true` with the specific ambiguity.
- If a required tool fails, return partial results with the failure noted in `caveats`.

## Tools available
- `tool_name_1`: <one-line description>. Use when <condition>.
- ...

## Examples
See few_shot.md for canonical examples.
```

Versioning: bump prompt version on any wording change. Major version on schema/contract change. Eval harness pins prompt version; comparing versions is a first-class operation.

## Schema design

Output schemas inherit from `AgentOutputBase`:

```python
from decimal import Decimal
from datetime import datetime
from typing import Literal
from pydantic import BaseModel, ConfigDict, Field

class AgentOutputBase(BaseModel):
    model_config = ConfigDict(strict=True, extra="forbid")

    request_id: str
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

Numbers go in a typed `numbers: dict[str, Decimal]` field, NEVER in free-text summaries that another agent or system has to parse.

Schemas are the contract between agents. Schema changes are breaking changes — bump the schema version, update the consumer, run consumer tests.

## Tool integration

Agent tools are MCP tools served by `mcp_servers/`. To add a tool to an agent:

1. Add the tool to the appropriate MCP server (or create a new one).
2. Register the tool name in `agents/<name>/tools.py` with explicit allowlist.
3. Document in the system prompt: when to use, what it returns.
4. Add eval cases that exercise the tool path.

Never give an agent more tools than it needs. Each tool is a degree of freedom; minimize the surface.

## Evals

Every agent has a golden dataset of `(input, expected_output_or_assertion)` pairs. The eval harness:

- Runs each case
- Validates output against schema (any failure = fail)
- Runs assertions (e.g., "research output for AAPL must mention iPhone OR Services revenue")
- Tracks: pass rate, schema-validation pass rate, p50/p99 latency, cost per case
- Compares against the previous run; flags regressions >3 percentage points

Adding a feature without adding eval cases is forbidden. The golden dataset grows with the agent.

## Common mistakes (do not repeat)

- ❌ Returning untyped JSON. Pydantic the output, even if the LLM gave you raw text.
- ❌ Floats anywhere near money. Decimals.
- ❌ "Helpful" agents that do more than their job. The Research Agent does NOT propose trades. The Trade Agent does NOT do research.
- ❌ Concatenating LLM strings into prompts without escaping. Use a template engine or structured prompt builder.
- ❌ Forgetting to propagate cost. Every LLM call returns cost; bubble it up to `cost_usd`.
- ❌ Logging raw inputs that may contain client PII. Use `redact()`.
- ❌ Bypassing Compliance. Trade Agent MUST call Compliance before returning a proposal.
- ❌ Creating an agent that talks to the user directly. Only the Orchestrator talks to users.

## When in doubt

- Read the existing `research_agent.py` as a reference implementation.
- Read `docs/agents/<your-agent>.md` for the spec, if it exists.
- Ask the user before improvising on financial logic, compliance, or anything user-facing.
