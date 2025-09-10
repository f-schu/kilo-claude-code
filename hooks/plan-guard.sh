#!/usr/bin/env bash
# plan-guard.sh - Pre-execution planning/subagent enforcement with optional blocking

set +e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Config (can be overridden via env)
CLAUDE_PLAN_GUARD_ENFORCE="${CLAUDE_PLAN_GUARD_ENFORCE:-true}"
CLAUDE_PLAN_GUARD_BLOCK_COMPLEX="${CLAUDE_PLAN_GUARD_BLOCK_COMPLEX:-true}"
CLAUDE_PLAN_GUARD_STRICT_FILE="${CLAUDE_PLAN_GUARD_STRICT_FILE:-.claude/plan-guard.strict}"

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}🧭 Plan Guard: Ensure plan + subagent allocation${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
cat >&2 <<'EOF'
Checklist:
- Task Contract written (scope, non-goals, constraints)
- Agent Allocation decided (primary + subagents)
- Subagent Contracts defined (inputs → outputs → success)
- Definition of Done set (tests, artifacts, acceptance)
Tip: Parallelize independent parts; use specialist agents when applicable.
EOF

# Proactively ensure a GitHub issue exists for the task (non-blocking)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -x "$SCRIPT_DIR/github-ops.sh" ]]; then
  "$SCRIPT_DIR/github-ops.sh" ensure || true
fi

# Read any stdin (Claude often passes tool metadata JSON); fall back to empty
CONTENT=""
if ! tty -s; then
  CONTENT=$(cat 2>/dev/null || true)
fi

# Heuristic complexity detection
is_complex=false
if echo "$CONTENT" | (command -v rg >/dev/null 2>&1 && rg -qi '(Write|Edit|MultiEdit|Task|sequential|Plan)' || grep -qiE '(Write|Edit|MultiEdit|Task|sequential|Plan)'); then
  # Look for multi-part/complex language
  if echo "$CONTENT" | (command -v rg >/dev/null 2>&1 && rg -qi '(and|,|;).*\b(implement|refactor|architect|migrate|pipeline|database|visualization|benchmark|deploy|ci|ml|agents?)' || grep -qiE '(and|,|;).*\b(implement|refactor|architect|migrate|pipeline|database|visualization|benchmark|deploy|ci|ml|agents?)'); then
    is_complex=true
  fi
fi

# Strict mode via toggle file: block on any write/edit regardless of complexity
if [[ -f "$CLAUDE_PLAN_GUARD_STRICT_FILE" ]]; then
if echo "$CONTENT" | (command -v rg >/dev/null 2>&1 && rg -q '"tool_name"\s*:\s*"(Write|Edit|MultiEdit)"' || grep -q '"tool_name"[[:space:]]*:[[:space:]]*"\(Write\|Edit\|MultiEdit\)"'); then
    echo -e "${RED}⛔ Strict plan required for this repository (toggle file detected).${NC}" >&2
    cat >&2 <<'EOF'
Please draft the following before proceeding:
1) Task Contract (scope, non-goals, constraints, acceptance)
2) Agent Allocation (primary + subagents) with roles
3) Subagent Contracts (inputs → outputs → success, return format)

Remove .claude/plan-guard.strict to disable strict mode.
EOF
    exit 2
  fi
fi

# If enforcement disabled or not complex, do not block
if [[ "$CLAUDE_PLAN_GUARD_ENFORCE" != "true" || "$CLAUDE_PLAN_GUARD_BLOCK_COMPLEX" != "true" || "$is_complex" != true ]]; then
  exit 0
fi

# Blocking message
echo -e "${RED}⛔ Complex task detected. Planning required before execution.${NC}" >&2
cat >&2 <<'EOF'
Please draft the following before proceeding:
1) Task Contract (scope, non-goals, constraints, acceptance)
2) Agent Allocation (primary + subagents) with roles
3) Subagent Contracts (inputs → outputs → success, return format)

After that, proceed with implementation.
EOF

# Exit 2 to keep session active until plan is produced
exit 2
