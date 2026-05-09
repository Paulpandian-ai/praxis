#!/usr/bin/env bash
# Auto-format files on write. Silent on success, surfaces errors only.

set -euo pipefail

input=$(cat)
path=$(echo "$input" | jq -r '.tool_input.file_path // ""')

case "$path" in
  *.py)
    if command -v ruff >/dev/null 2>&1; then
      ruff format "$path" 2>/dev/null || true
      ruff check --fix --unsafe-fixes "$path" 2>/dev/null || true
    fi
    ;;
  *.ts|*.tsx|*.js|*.jsx|*.json)
    if command -v biome >/dev/null 2>&1; then
      biome format --write "$path" 2>/dev/null || true
    fi
    ;;
esac

exit 0
