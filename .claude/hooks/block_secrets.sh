#!/usr/bin/env bash
# Block commits/edits that contain likely secrets.
# Hook input: JSON on stdin with tool_input.file_path and tool_input.content.

set -euo pipefail

input=$(cat)
content=$(echo "$input" | jq -r '.tool_input.content // .tool_input.new_string // ""')
path=$(echo "$input" | jq -r '.tool_input.file_path // ""')

# Patterns to flag (high-signal, low false-positive)
patterns=(
  'AKIA[0-9A-Z]{16}'                        # AWS access key ID
  'aws_secret_access_key\s*=\s*[A-Za-z0-9/+=]{40}'
  'sk-[a-zA-Z0-9]{32,}'                     # API keys (OpenAI-style)
  'sk-ant-[a-zA-Z0-9_-]{20,}'               # Anthropic keys
  'xox[baprs]-[A-Za-z0-9-]{10,}'            # Slack tokens
  '-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----'
  'mongodb\+srv://[^:]+:[^@]+@'             # MongoDB connection string with creds
  'postgres(ql)?://[^:]+:[^@]+@'            # Postgres connection string with creds
)

for pattern in "${patterns[@]}"; do
  if echo "$content" | grep -qE "$pattern"; then
    echo "{\"decision\": \"block\", \"reason\": \"Possible secret detected in $path. Use AWS Secrets Manager. Pattern matched: $pattern\"}"
    exit 0
  fi
done

# Block .env file edits unless it's .env.example
if [[ "$path" == *".env" ]] && [[ "$path" != *".env.example" ]]; then
  echo "{\"decision\": \"block\", \"reason\": \".env files are not allowed. Use .env.example as a template; real values go in AWS Secrets Manager.\"}"
  exit 0
fi

exit 0
