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
# Policy: permissive | guided | strict
POLICY="${CLAUDE_PLAN_GUARD_POLICY:-}"
if [[ -z "$POLICY" && -f .claude/plan-guard.policy ]]; then
  POLICY="$(tr -d '\r' < .claude/plan-guard.policy | head -n1 | xargs)"
fi
case "${POLICY,,}" in
  permissive|guided|strict) ;;
  *) POLICY="guided" ;;
esac
NEW_FILES_WARN_THRESHOLD="${CLAUDE_NEW_FILES_WARN_THRESHOLD:-}"
if [[ -z "$NEW_FILES_WARN_THRESHOLD" && -f .claude/new-files-warn-threshold ]]; then
  NEW_FILES_WARN_THRESHOLD="$(tr -d '\r' < .claude/new-files-warn-threshold | head -n1 | xargs)"
fi
case "$NEW_FILES_WARN_THRESHOLD" in
  '' ) NEW_FILES_WARN_THRESHOLD=5 ;;
  * ) if ! echo "$NEW_FILES_WARN_THRESHOLD" | grep -qE '^[0-9]+$'; then NEW_FILES_WARN_THRESHOLD=5; fi ;;
esac

# Small-edit passthrough configuration (max changed lines)
SMALL_EDIT_MAX_LINES="${CLAUDE_SMALL_EDIT_MAX_LINES:-}"
if [[ -z "$SMALL_EDIT_MAX_LINES" && -f .claude/small-edit-max-lines ]]; then
  SMALL_EDIT_MAX_LINES="$(tr -d '\r' < .claude/small-edit-max-lines | head -n1 | xargs)"
fi
case "$SMALL_EDIT_MAX_LINES" in
  '' ) SMALL_EDIT_MAX_LINES=10 ;;
  * ) if ! echo "$SMALL_EDIT_MAX_LINES" | grep -qE '^[0-9]+$'; then SMALL_EDIT_MAX_LINES=10; fi ;;
esac

# Plan freshness TTL (minutes)
PLAN_TTL_MIN="${CLAUDE_PLAN_TTL_MIN:-}"
if [[ -z "$PLAN_TTL_MIN" && -f .claude/plan-ttl-min ]]; then
  PLAN_TTL_MIN="$(tr -d '\r' < .claude/plan-ttl-min | head -n1 | xargs)"
fi
case "$PLAN_TTL_MIN" in
  '' ) PLAN_TTL_MIN=45 ;;
  * ) if ! echo "$PLAN_TTL_MIN" | grep -qE '^[0-9]+$'; then PLAN_TTL_MIN=45; fi ;;
esac

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
  "$SCRIPT_DIR/github-ops.sh" ensure || echo -e "${YELLOW}Warning:${NC} GitHub ensure failed (check gh auth/repo permissions)." >&2
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

# Fresh plan detection
has_fresh_plan=false
if command -v jq >/dev/null 2>&1 && [[ -f .claude/plan.json ]]; then
  # Check required fields and age
  if jq -er '.task_contract.scope and (.agent_allocation|length>=0) and (.subagent_contracts|length>=0)' .claude/plan.json >/dev/null 2>&1; then
    # Check age
    now=$(date +%s)
    mtime=$(stat -c %Y .claude/plan.json 2>/dev/null || stat -f %m .claude/plan.json 2>/dev/null || echo 0)
    age_min=$(( (now - mtime) / 60 ))
    if [[ "$age_min" -le "$PLAN_TTL_MIN" ]]; then
      has_fresh_plan=true
    fi
  fi
fi

# Label-based relax: if current issue has 'fix' label, don't block
relax=false
if [[ -x "$SCRIPT_DIR/github-ops.sh" && -f .claude/.current_issue ]]; then
  if command -v gh >/dev/null 2>&1; then
    if gh auth status >/dev/null 2>&1; then
      ISSUE_NUM="$(cat .claude/.current_issue 2>/dev/null)"
      if [[ -n "$ISSUE_NUM" ]]; then
        LABELS="$(gh issue view "$ISSUE_NUM" --json labels --jq '.labels[].name' 2>/dev/null || true)"
        if echo "$LABELS" | awk 'BEGIN{IGNORECASE=1} /fix/ {found=1} END{exit !found}'; then
          relax=true
          echo -e "${YELLOW}Plan-guard relaxed due to 'fix' label on issue #${ISSUE_NUM}.${NC}" >&2
        fi
      fi
    fi
  fi
fi

# Small-edit passthrough: allow single-file edits under threshold, no new files, no schema/API changes
small_edit_ok=false
TOOL=""
if command -v jq >/dev/null 2>&1; then
  TOOL=$(echo "$CONTENT" | jq -r '.tool_name // empty' 2>/dev/null)
else
  TOOL=$(echo "$CONTENT" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]\+\)".*/\1/p' | head -n1)
fi
if echo "$TOOL" | grep -qiE '^(Write|Edit)$'; then
  # Extract target file path
  target=""
  if command -v jq >/dev/null 2>&1; then
    target=$(echo "$CONTENT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
  else
    target=$(echo "$CONTENT" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]\+\)".*/\1/p' | head -n1)
  fi
  # Estimate line count if possible
  line_estimate=""
  if command -v jq >/dev/null 2>&1; then
    body=$(echo "$CONTENT" | jq -r '.tool_input.new_content // .tool_input.content // .tool_input.text // .tool_input.replacement // empty' 2>/dev/null)
    if [[ -n "$body" && "$body" != "null" ]]; then
      line_estimate=$(printf "%s" "$body" | awk 'END{print NR}')
    fi
  fi
  # No untracked files?
  nf=0
  if [[ -d .git ]]; then
    nf=$(git status --porcelain 2>/dev/null | awk '$1=="??"{c++} END{print c+0}')
  fi
  # Schema/API change patterns (block if present)
  schema_api=false
  if echo "$CONTENT" | (command -v rg >/dev/null 2>&1 && rg -qi '(CREATE|DROP|ALTER)\s+TABLE|add_api_route|router\.|@app\.|OpenAPI' || grep -qiE '(CREATE|DROP|ALTER)[[:space:]]+TABLE|add_api_route|router\.|@app\.|OpenAPI'); then
    schema_api=true
  fi
  if [[ "$schema_api" != true && "$nf" -eq 0 && -n "$target" && -n "$line_estimate" && "$line_estimate" -le "$SMALL_EDIT_MAX_LINES" ]]; then
    small_edit_ok=true
    echo -e "${YELLOW}Small-edit passthrough:${NC} allowing single-file edit ($target) under ${SMALL_EDIT_MAX_LINES} lines." >&2
  fi
fi

# Bash small-edit passthrough: short scripts without dangerous commands or schema/API patterns
if echo "$TOOL" | grep -qi '^Bash$'; then
  # Count lines
  lines=$(echo "$CONTENT" | wc -l | awk '{print $1}')
  dangerous=false
  if echo "$CONTENT" | (command -v rg >/dev/null 2>&1 && rg -qi '\brm\s+-rf|\bmv\s|\bcp\s+-r|find\s+.*-exec' || grep -qiE '\brm[[:space:]]+-rf|\bmv[[:space:]]|\bcp[[:space:]]+-r|find[[:space:]].*-exec'); then
    dangerous=true
  fi
  schema_api=false
  if echo "$CONTENT" | (command -v rg >/dev/null 2>&1 && rg -qi '(CREATE|DROP|ALTER)\s+TABLE|add_api_route|router\.|@app\.|OpenAPI' || grep -qiE '(CREATE|DROP|ALTER)[[:space:]]+TABLE|add_api_route|router\.|@app\.|OpenAPI'); then
    schema_api=true
  fi
  if [[ "$dangerous" != true && "$schema_api" != true && "$lines" -le "$SMALL_EDIT_MAX_LINES" ]]; then
    small_edit_ok=true
    echo -e "${YELLOW}Small-edit passthrough:${NC} allowing short Bash snippet under ${SMALL_EDIT_MAX_LINES} lines." >&2
  fi
fi

# Strict mode via toggle file: block on any write/edit regardless of complexity
if [[ -f "$CLAUDE_PLAN_GUARD_STRICT_FILE" ]]; then
  if [[ "$relax" != true && "$small_edit_ok" != true && "$has_fresh_plan" != true ]] && echo "$TOOL" | grep -qiE '^(Write|Edit|MultiEdit|Bash)$'; then
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
if [[ "${POLICY}" == "permissive" || "$relax" == true || "$small_edit_ok" == true || "$has_fresh_plan" == true || "$CLAUDE_PLAN_GUARD_ENFORCE" != "true" || ( "${POLICY}" == "guided" && "$CLAUDE_PLAN_GUARD_BLOCK_COMPLEX" != "true" ) || "$is_complex" != true ]]; then
  # Warn if there are many untracked new files without acknowledgment
  if [[ -d .git ]]; then
    NF=$(git status --porcelain 2>/dev/null | awk '$1=="??"{c++} END{print c+0}')
    if [[ "$NF" -gt "$NEW_FILES_WARN_THRESHOLD" && ! -f .claude/ack-many-new-files ]]; then
      echo -e "${YELLOW}Warning:${NC} Detected $NF untracked new files. Consider adding a plan note or create .claude/ack-many-new-files to acknowledge bulk file creation." >&2
    fi
  fi
  # Pretty summary if rich is available
  if command -v python3 >/dev/null 2>&1; then
    cat <<JSON | python3 "$SCRIPT_DIR/rich-summary.py" 2>/dev/null || true
{
  "title": "Plan Guard — PASS/RELAX",
  "style": "green",
  "fields": [
    ["Complex", "${is_complex}"],
    ["Relax by label", "${relax}"],
    ["Small edit ok", "${small_edit_ok}"],
    ["Untracked files", "${NF:-0}"],
    ["Warn threshold", "${NEW_FILES_WARN_THRESHOLD}"]
  ],
  "notes": [
    "Proceeding without blocking."
  ]
}
JSON
  fi
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

# If no plan file exists, show quick template hint
if [[ ! -f .claude/plan.json ]]; then
  cat >&2 <<'EOF'
Plan template (save to .claude/plan.json):
{
  "task_contract": {
    "scope": "one sentence",
    "non_goals": ["out of scope"],
    "constraints": ["env","time"],
    "acceptance": ["tests to pass","artifacts"]
  },
  "agent_allocation": [],
  "subagent_contracts": []
}
EOF
fi

# Pretty block summary if rich is available
if command -v python3 >/dev/null 2>&1; then
  # Compute NF for display
  NF_BLOCK=0
  if [[ -d .git ]]; then
    NF_BLOCK=$(git status --porcelain 2>/dev/null | awk '$1=="??"{c++} END{print c+0}')
  fi
  cat <<JSON | python3 "$SCRIPT_DIR/rich-summary.py" 2>/dev/null || true
{
  "title": "Plan Guard — BLOCKED",
  "style": "yellow",
  "fields": [
    ["Complex", "${is_complex}"],
    ["Relax by label", "${relax}"],
    ["Small edit ok", "${small_edit_ok}"],
    ["Strict mode", "$( [[ -f "$CLAUDE_PLAN_GUARD_STRICT_FILE" ]] && echo true || echo false )"],
    ["Untracked files", "${NF_BLOCK}"],
    ["Warn threshold", "${NEW_FILES_WARN_THRESHOLD}"]
  ],
  "notes": [
    "Provide Task Contract, Agent Allocation, Subagent Contracts.",
    "Or add 'fix' label to relax for bug-fix flows."
  ]
}
JSON
fi

# Exit 2 to keep session active until plan is produced
exit 2
