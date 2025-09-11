#!/usr/bin/env bash
set -euo pipefail

# Read stdin JSON (Claude Code hook payload)
stdin_json=$(cat)
transcript_path=$(echo "$stdin_json" | jq -r '.transcript_path // empty')
current_prompt=$(echo "$stdin_json" | jq -r '.prompt // empty' 2>/dev/null || true)

query="${current_prompt:-}"

if [[ -z "$query" && -n "${transcript_path:-}" && -f "$transcript_path" ]]; then
  # Try to extract the last user text line from the transcript (NDJSON-like)
  last_user_line=$(grep '"role":"user"' "$transcript_path" | tail -n 1 || true)
  if [[ -n "$last_user_line" ]]; then
    query=$(jq -r '.message.content[0].text // empty' <<< "$last_user_line" 2>/dev/null || true)
  fi
fi

query=${query:-}
if [[ -z "$query" ]]; then
  exit 0
fi

# Determine paths
PROJECT_DIR="${PWD}"
CLAUDE_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"

# Force per-project DB path and namespace
export APOGEEMIND_DUCKDB_PATH="${APOGEEMIND_DUCKDB_PATH:-$PROJECT_DIR/apogeemind/apogeemind.duckdb}"
if [[ -z "${APOGEEMIND_NAMESPACE:-}" ]]; then
  export APOGEEMIND_NAMESPACE="code:$(basename "$PROJECT_DIR")"
fi

# Call the Python injector from the .claude repo
python3 "$CLAUDE_REPO_ROOT/scripts/apogeemind_inject.py" --query "$query"
exit 0
