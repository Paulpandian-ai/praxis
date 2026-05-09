#!/usr/bin/env bash
# Block bash commands that could destroy data, push to production, or expose secrets.

set -euo pipefail

input=$(cat)
cmd=$(echo "$input" | jq -r '.tool_input.command // ""')

# Patterns to block
declare -a blocked_patterns=(
  'rm -rf /'
  'rm -rf \\$'
  ':(){:|:&};:'                    # fork bomb
  'aws iam delete'
  'aws s3 rm.*--recursive'
  'aws secretsmanager delete-secret'
  'cdk destroy.*--force'
  'git push.*--force.*main'
  'git push.*--force.*master'
  'git push.*-f.*main'
  'kubectl delete namespace'
  'dd if=.*of=/dev/'
  'mkfs\.'
  'shutdown'
  'reboot'
  'halt'
)

for pattern in "${blocked_patterns[@]}"; do
  if echo "$cmd" | grep -qE "$pattern"; then
    echo "{\"decision\": \"block\", \"reason\": \"Blocked dangerous command pattern: $pattern\"}"
    exit 0
  fi
done

# Warn (but don't block) on direct AWS production-like changes
if echo "$cmd" | grep -qE 'AWS_PROFILE=production|--profile.*production|--profile.*prod'; then
  echo "{\"decision\": \"block\", \"reason\": \"Direct production AWS profile use is blocked. Deploy through CI/CD pipeline.\"}"
  exit 0
fi

exit 0
