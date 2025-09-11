#!/usr/bin/env bash
set -euo pipefail

# Optional arg: project directory where DB should live (default: current dir)
PROJECT_DIR="${1:-$(pwd)}"

# Resolve repo root for this .claude repo (where scripts live)
CLAUDE_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"

# Set per-project defaults if not overridden by env
export APOGEEMIND_DUCKDB_PATH="${APOGEEMIND_DUCKDB_PATH:-$PROJECT_DIR/apogeemind/apogeemind.duckdb}"
if [[ -z "${APOGEEMIND_NAMESPACE:-}" ]]; then
  base="$(basename "$PROJECT_DIR")"
  export APOGEEMIND_NAMESPACE="code:${base}"
fi

python3 "$CLAUDE_REPO_ROOT/scripts/apogeemind_init.py"
exit 0
