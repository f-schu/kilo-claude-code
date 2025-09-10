#!/usr/bin/env bash
set -euo pipefail

# mkplan.sh — generate .claude/plan.json and optionally set TTL
# Usage (with GNU make):
#   make plan scope="Fix drop order for genome tables" \
#            non_goals="don't refactor unrelated modules" \
#            constraints="prod data unaffected, time<30m" \
#            acceptance="unit tests green, drop order correct" \
#            ttl=45

SCOPE=${1:-${scope:-${SCOPE:-}}}
NON_GOALS=${2:-${non_goals:-${NON_GOALS:-}}}
CONSTRAINTS=${3:-${constraints:-${CONSTRAINTS:-}}}
ACCEPTANCE=${4:-${acceptance:-${ACCEPTANCE:-}}}
TTL_MIN=${5:-${ttl:-${TTL:-}}}

CLAUDE_DIR=".claude"
PLAN_FILE="${CLAUDE_DIR}/plan.json"
TTL_FILE="${CLAUDE_DIR}/plan-ttl-min"

mkdir -p "$CLAUDE_DIR"

now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

csv_to_json_array() {
  local csv="$1"
  # Split by comma, trim spaces, drop empties
  awk -v RS=',' '{gsub(/^\s+|\s+$/,"",$0); if(length($0)) printf("%s\"%s\"", NR>1?",":"", $0)}' <<< "${csv}"
}

escape_json() {
  python3 - << 'PY' "$1"
import json,sys
print(json.dumps(sys.argv[1]))
PY
}

SCOPE_ESC=${SCOPE:+$(escape_json "$SCOPE")}

# Default TTL 45 if unset/invalid
if [[ -z "${TTL_MIN:-}" ]] || ! [[ "$TTL_MIN" =~ ^[0-9]+$ ]]; then
  TTL_MIN=45
fi

# Build JSON arrays
NON_GOALS_JSON=$( [[ -n "${NON_GOALS:-}" ]] && printf "[%s]" "$(csv_to_json_array "$NON_GOALS")" || printf '[]' )
CONSTRAINTS_JSON=$( [[ -n "${CONSTRAINTS:-}" ]] && printf "[%s]" "$(csv_to_json_array "$CONSTRAINTS")" || printf '[]' )
ACCEPTANCE_JSON=$( [[ -n "${ACCEPTANCE:-}" ]] && printf "[%s]" "$(csv_to_json_array "$ACCEPTANCE")" || printf '[]' )

cat > "$PLAN_FILE" <<JSON
{
  "generated_at": "$(now_iso)",
  "task_contract": {
    "scope": ${SCOPE_ESC:-""},
    "non_goals": ${NON_GOALS_JSON},
    "constraints": ${CONSTRAINTS_JSON},
    "acceptance": ${ACCEPTANCE_JSON}
  },
  "agent_allocation": [],
  "subagent_contracts": []
}
JSON

echo "$TTL_MIN" > "$TTL_FILE"

if command -v jq >/dev/null 2>&1; then
  tmp=$(mktemp)
  jq . "$PLAN_FILE" > "$tmp" && mv "$tmp" "$PLAN_FILE"
fi

echo "Wrote $PLAN_FILE (TTL ${TTL_MIN}m)"
exit 0

