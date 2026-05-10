# Praxis

A multi-agent AI platform that acts as a co-worker for asset managers — research, risk, compliance, execution, and reporting agents working in concert behind an orchestrator. Praxis is **decision support** for a licensed fiduciary; nothing that touches money executes without human approval.

> **Read [CLAUDE.md](CLAUDE.md) before contributing.** It is the persistent project context — mission, architecture, tech stack, code conventions, and the non-negotiable rules.

## Documents

- [CLAUDE.md](CLAUDE.md) — persistent project context (read first)
- [docs/architecture.md](docs/architecture.md) — system design, ADRs
- [docs/data-contracts.md](docs/data-contracts.md) — canonical Pydantic schemas
- [prompts/PHASED_BUILD_PLAN.md](prompts/PHASED_BUILD_PLAN.md) — phased build prompts for Claude Code

## Quickstart

Prerequisites: Python 3.12, Node 20+, pnpm 9, [uv](https://docs.astral.sh/uv/), Docker, GNU make.

```bash
# 1. Install all Python and JS dependencies
make install

# 2. Start local infra (Postgres+TimescaleDB, OpenSearch, MinIO)
make docker-up

# 3. Run the full check suite (format, lint, type, unit tests)
make check

# 4. Smoke evals
make eval-fast
```

## Common targets

| target | what it does |
|--------|--------------|
| `make install` | install Python (uv) + frontend (pnpm) deps |
| `make check` | format + lint + type + unit tests |
| `make test` | unit + integration tests |
| `make eval` | full golden-set evals |
| `make eval-fast` | smoke evals (~5 min) |
| `make schemas` | regenerate TS types from Pydantic schemas |
| `make docker-up` / `make docker-down` | start/stop local infra |
| `make dev` | run backend + frontend in dev mode |

## License

MIT — see [LICENSE](LICENSE).
