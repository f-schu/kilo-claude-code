#!/usr/bin/env bash
set -euo pipefail

stdin_json=$(cat)
transcript_path=$(echo "$stdin_json" | jq -r '.transcript_path // empty')

user_text=""
assistant_text=""

if [[ -n "${transcript_path:-}" && -f "$transcript_path" ]]; then
  # Extract last user and last assistant textual messages
  last_user_line=$(grep '"role":"user"' "$transcript_path" | tail -n 1 || true)
  last_assistant_line=$(grep '"role":"assistant"' "$transcript_path" | tail -n 1 || true)

  if [[ -n "$last_user_line" ]]; then
    user_text=$(jq -r '.message.content[0].text // empty' <<< "$last_user_line" 2>/dev/null || true)
  fi
  if [[ -n "$last_assistant_line" ]]; then
    assistant_text=$(jq -r '.message.content[0].text // empty' <<< "$last_assistant_line" 2>/dev/null || true)
  fi
fi

if [[ -z "$user_text" && -z "$assistant_text" ]]; then
  exit 0
fi

# Determine paths
PROJECT_DIR="${PWD}"
CLAUDE_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"

# Force per-project DB path and namespace
export MEMORI_DUCKDB_PATH="${MEMORI_DUCKDB_PATH:-$PROJECT_DIR/memori/memori.duckdb}"
if [[ -z "${MEMORI_NAMESPACE:-}" ]]; then
  export MEMORI_NAMESPACE="code:$(basename "$PROJECT_DIR")"
fi

# Call the Python recorder from the .claude repo
python3 "$CLAUDE_REPO_ROOT/scripts/memori_local_record.py" --user "$user_text" --assistant "$assistant_text"
exit 0
