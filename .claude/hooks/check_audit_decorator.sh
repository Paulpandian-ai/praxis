#!/usr/bin/env bash
# At session end, scan agent files to ensure run() methods have @audited decorator.
# Advisory only — surfaces a warning if missing.

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
violations=()

if [ -d "$repo_root/agents" ]; then
  while IFS= read -r file; do
    # Skip _shared, tests, __init__
    case "$file" in
      */_shared/*|*test_*|*/__init__.py) continue ;;
    esac

    # Check for `async def run(` without `@audited` on the line above
    if grep -qE 'async def run\(' "$file"; then
      if ! grep -B 3 'async def run(' "$file" | grep -q '@audited'; then
        violations+=("$file: run() method missing @audited decorator")
      fi
    fi
  done < <(find "$repo_root/agents" -name "agent.py" 2>/dev/null)
fi

if [ ${#violations[@]} -gt 0 ]; then
  echo "{\"systemMessage\": \"⚠️  Audit decorator check found ${#violations[@]} issue(s):\\n$(printf '%s\\n' "${violations[@]}")\"}"
fi

exit 0
