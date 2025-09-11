#!/usr/bin/env bash
set -euo pipefail

# Read stdin JSON (Claude Code hook payload)
stdin_json=$(cat)
transcript_path=$(echo "$stdin_json" | jq -r '.transcript_path // empty')
current_prompt=$(echo "$stdin_json" | jq -r '.prompt // empty' 2>/dev/null || true)

query="${current_prompt:-}"

if [[ -z "$query" && -n "${transcript_path:-}" && -f "$transcript_path" ]]; then
  # Try to extract the last user text line from the transcript (NDJSON-like)
  # We search for lines that look like role=user and have message.content[0].text
  # Fallbacks are best-effort.
  last_user_line=$(grep '"role":"user"' "$transcript_path" | tail -n 1 || true)
  if [[ -n "$last_user_line" ]]; then
    # Try to parse text via jq; ignore errors
    query=$(jq -r '.message.content[0].text // empty' <<< "$last_user_line" 2>/dev/null || true)
  fi
fi

query=${query:-}
if [[ -z "$query" ]]; then
  # Nothing to inject
  exit 0
fi

# Call the Python injector to print a <system-reminder> block
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(git rev-parse --show-toplevel 2>/dev/null || echo "$(pwd)")"
python3 "$repo_root/scripts/memori_local_inject.py" --query "$query"
exit 0

