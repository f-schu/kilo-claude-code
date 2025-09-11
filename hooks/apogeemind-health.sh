#!/usr/bin/env bash
set -euo pipefail

# Determine paths
PROJECT_DIR="${PWD}"
CLAUDE_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"

# Per-project defaults
export APOGEEMIND_DUCKDB_PATH="${APOGEEMIND_DUCKDB_PATH:-$PROJECT_DIR/apogeemind/apogeemind.duckdb}"
if [[ -z "${APOGEEMIND_NAMESPACE:-}" ]]; then
  export APOGEEMIND_NAMESPACE="code:$(basename "$PROJECT_DIR")"
fi

# If APOGEEMIND_HEALTH_TO_CONTEXT=1, add --to-context
args=()
if [[ "${APOGEEMIND_HEALTH_TO_CONTEXT:-0}" == "1" ]]; then
  args+=("--to-context")
fi

python3 "$CLAUDE_REPO_ROOT/scripts/apogeemind_health.py" "${args[@]}"
exit 0

