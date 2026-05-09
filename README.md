# Build guide — Agentic Asset Management Platform

This package contains everything Claude Code needs to build the platform discussed in our previous conversation. It is structured so you can drop it into an empty repository and begin building immediately.

## What's in this package

```
asset-mgmt-build/
├── CLAUDE.md                          # Persistent project context (READ FIRST)
├── Makefile                           # Common commands
├── .claude/
│   ├── settings.json                  # Claude Code permissions and hooks
│   ├── hooks/
│   │   ├── block_secrets.sh           # Blocks accidental secret commits
│   │   ├── block_float_money.sh       # Enforces Decimal for monetary values
│   │   ├── block_dangerous_bash.sh    # Blocks rm -rf, force push, etc.
│   │   ├── format_on_write.sh         # Auto-runs ruff/biome on save
│   │   └── check_audit_decorator.sh   # Verifies @audited on agent run() methods
│   ├── commands/
│   │   ├── new-agent.md               # /new-agent <name>
│   │   ├── eval.md                    # /eval <agent>
│   │   ├── compliance-check.md        # /compliance-check
│   │   └── context-checkpoint.md      # /context-checkpoint (before /clear)
│   └── skills/
│       ├── agent-design/              # How to build any agent in this system
│       └── financial-math/            # Money math rules (Decimal, returns, etc.)
├── docs/
│   ├── architecture.md                # System design + ADRs
│   └── data-contracts.md              # Canonical Pydantic schemas
└── prompts/
    └── PHASED_BUILD_PLAN.md           # Step-by-step prompts for Claude Code
```

## How to use it

### Step 1: Create the repository

```bash
mkdir my-asset-mgmt-platform
cd my-asset-mgmt-platform
git init
```

### Step 2: Drop these files in

Copy the entire contents of `asset-mgmt-build/` into the repo root, preserving the directory structure. Then:

```bash
chmod +x .claude/hooks/*.sh
git add .
git commit -m "chore: initialize project context and Claude Code config"
```

### Step 3: Verify Claude Code reads the context

```bash
claude
```

In the session, ask: "Read CLAUDE.md and tell me what this project is." If the response correctly summarizes the multi-agent platform, the persistent context is wired up.

### Step 4: Begin Phase 0

Open `prompts/PHASED_BUILD_PLAN.md` and paste **Prompt 0.1** into Claude Code. Use plan mode (Shift+Tab). Review the plan, then proceed.

After Phase 0 completes, you have a working project skeleton with CI, formatting, type checks, and the foundation directory structure.

### Step 5: Continue through the phases

Each phase builds on the previous. The recommended cadence:
- **Phase 0**: 1 session (~30 min)
- **Phase 1**: 1-2 sessions (foundations)
- **Phase 2**: 2-3 sessions (orchestrator + research + earnings)
- **Phase 3**: 3-4 sessions (portfolio context + risk + watchlist)
- **Phase 4**: 3-4 sessions (compliance + portfolio construction + trade)
- **Phase 5**: 4-5 sessions (quant, macro, news, reporting, tax)
- **Phase 6**: 2-3 sessions (hardening + observability)
- **Phase 7**: 2 sessions (deployment + onboarding)

Total: ~18-25 focused Claude Code sessions to a v1 platform. At ~2-4 hours per session, that's 5-10 weeks of solo build time, less if you parallelize on the front-end.

## The most important rules

If you take only three things from this package, take these:

1. **CLAUDE.md is the contract.** Claude Code will read it on every session. Whenever Claude makes a mistake worth not repeating, add a line to section 16. This is how the system improves over time.

2. **The hooks are non-negotiable.** They enforce the rules that, if violated, create real-world incidents (secrets in git, float in money math, force-push to main, missing audit logs). They run silently in the background and block bad changes before they hit disk.

3. **Schemas before logic, every time.** Pydantic models in `_shared/schemas/` are the source of truth. They define the contracts between agents. When you change a schema, you change a contract — and Claude Code is good at refactoring across boundaries when the schema is the anchor.

## Customizing for your situation

Several things in CLAUDE.md and the build plan are placeholders you should adjust:

- **Custodian adapter**: Phase 3.1 picks one to start. Tell Claude which (Schwab, Fidelity, IBKR, etc.).
- **Market data provider**: stub in v1. Decide before Phase 5 (Polygon, IEX Cloud, Bloomberg, Refinitiv).
- **Compliance rules**: the v1 rule types in `_shared/schemas/compliance.py` are common ones. Add your specific mandate types.
- **Deployment region**: CDK stacks default to `us-east-1`. Change in `infra/app.py`.
- **Model selection**: defaults to Opus 4.7 / Sonnet 4.6 / Haiku 4.5 split. Adjust per-agent in `agents/_shared/llm.py` config based on your cost vs accuracy trade-offs.

## Things this guide deliberately does NOT do

- It doesn't pick a specific Seeking Alpha integration approach in code. Their ToS shifts and there's no public-API contract for an asset manager use case. You'll have to make a call (subscriber-authenticated session, official partner agreement if your AUM justifies it, or licensed feed). The MCP server abstraction lets you swap implementations.
- It doesn't include a real OMS adapter — only a dry-run stub. Real OMS integration depends on your broker(s).
- It doesn't include a backtesting framework. Backtesting is its own project; the eval harness handles agent correctness, not strategy alpha.
- It doesn't address GIPS verification or 40-Act registration. Those are legal/compliance projects, not engineering ones.

## Final thought

The hardest part of an agentic system is not the agents — it's the contracts between them, the audit trail, the compliance layer, and the human-in-the-loop gates. Most "AI for investing" startups skimp on those because they're unsexy. They're also what makes the difference between a demo and a production tool an asset manager will actually trust with their book.

This guide front-loads the unsexy work. Schemas, audit, compliance, evals, hooks. Get those right and the agents — the parts that look impressive in screenshots — fall into place.
