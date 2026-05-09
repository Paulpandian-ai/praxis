.PHONY: help install check fmt lint type test test-unit test-integration test-e2e \
	eval eval-fast schemas dev docker-up docker-down clean

help:
	@echo "Common targets:"
	@echo "  install         Install all Python and JS dependencies"
	@echo "  check           Run all checks (fmt, lint, type, unit tests)"
	@echo "  fmt             Format Python and TypeScript"
	@echo "  lint            Lint without formatting"
	@echo "  type            Run mypy"
	@echo "  test            Run all tests (unit + integration)"
	@echo "  test-unit       Run unit tests only"
	@echo "  test-integration  Run integration tests (requires docker-up)"
	@echo "  test-e2e        Run Playwright e2e tests"
	@echo "  eval            Run all golden-set evals"
	@echo "  eval-fast       Run smoke evals (~5 min)"
	@echo "  schemas         Regenerate TS types from Pydantic schemas"
	@echo "  dev             Start backend + frontend in dev mode"
	@echo "  docker-up       Start local stack (Postgres, OpenSearch, MinIO)"
	@echo "  docker-down     Stop local stack"

install:
	uv sync
	cd frontend && pnpm install

fmt:
	uv run ruff format .
	uv run ruff check --fix --unsafe-fixes .
	cd frontend && pnpm biome format --write .

lint:
	uv run ruff check .
	cd frontend && pnpm biome check .

type:
	uv run mypy agents/ mcp_servers/ data/ _shared/ 2>/dev/null || uv run mypy .
	cd frontend && pnpm tsc --noEmit

test-unit:
	uv run pytest tests/unit agents/ mcp_servers/ -x --cov --cov-report=term-missing

test-integration:
	uv run pytest tests/integration -x

test-e2e:
	cd frontend && pnpm playwright test

test: test-unit test-integration

check: fmt lint type test-unit
	@echo "✅ All checks passed."

eval:
	uv run python -m evals.runners.run_all --output evals/reports/

eval-fast:
	uv run python -m evals.runners.run_all --smoke --output evals/reports/

schemas:
	uv run python scripts/generate_ts_schemas.py
	cd frontend && pnpm biome format --write lib/schemas/

dev:
	docker-compose up -d
	(cd frontend && pnpm dev) & \
	uv run python -m agents.orchestrator.local_runner

docker-up:
	docker-compose -f infra/local/docker-compose.yml up -d

docker-down:
	docker-compose -f infra/local/docker-compose.yml down

clean:
	find . -type d -name __pycache__ -exec rm -rf {} +
	find . -type d -name .pytest_cache -exec rm -rf {} +
	find . -type d -name .mypy_cache -exec rm -rf {} +
	rm -rf .ruff_cache htmlcov coverage.xml
	cd frontend && rm -rf .next node_modules/.cache
