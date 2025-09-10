#!/usr/bin/env bash
# completion-guard.sh - Block "done" if lint/tests aren’t green

set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_HELPERS="$SCRIPT_DIR/common-helpers.sh"
[[ -f "$COMMON_HELPERS" ]] && source "$COMMON_HELPERS"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
echo -e "${BLUE}✅ Completion Guard: Verifying Definition of Done${NC}" >&2
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2

FAIL=0
ADDITIVE_ONLY=0
IMPACT_OK=1

# Logs
TODAY="$(date +%Y%m%d)"
RUNSTAMP="$(date +%Y%m%d_%H%M%S)"
LOG_DIR="logs/${TODAY}"
mkdir -p "$LOG_DIR"
LINT_LOG="${LOG_DIR}/completion-guard_lint_${RUNSTAMP}.log"
TEST_LOG="${LOG_DIR}/completion-guard_test_${RUNSTAMP}.log"

# Task mode overrides (allow review-only tasks to pass without green tests)
TASK_MODE="${CLAUDE_TASK_MODE:-}"
if [[ -z "$TASK_MODE" && -f .claude/task-mode ]]; then
  TASK_MODE="$(tr -d '\r' < .claude/task-mode | head -n1 | xargs)"
fi
ALLOW_FAILING_TESTS="${CLAUDE_ALLOW_FAILING_TESTS:-}"
if [[ -z "$ALLOW_FAILING_TESTS" && -f .claude/allow-failing-tests ]]; then
  ALLOW_FAILING_TESTS=1
fi
TEST_GATE_OPTIONAL=false
if [[ "$TASK_MODE" == "review" || "$ALLOW_FAILING_TESTS" == "1" || "$ALLOW_FAILING_TESTS" == "true" ]]; then
  TEST_GATE_OPTIONAL=true
fi

# Heuristic: If current GitHub issue has label 'review', allow failing tests
if [[ "$TEST_GATE_OPTIONAL" != true && -x "$SCRIPT_DIR/github-ops.sh" && -f .claude/.current_issue ]]; then
  if command -v gh >/dev/null 2>&1; then
    if gh auth status >/dev/null 2>&1; then
      ISSUE_NUM="$(cat .claude/.current_issue 2>/dev/null)"
      if [[ -n "$ISSUE_NUM" ]]; then
        LABELS="$(gh issue view "$ISSUE_NUM" --json labels --jq '.labels[].name' 2>/dev/null || true)"
        if echo "$LABELS" | awk 'BEGIN{IGNORECASE=1} /review/ {found=1} END{exit !found}'; then
          TEST_GATE_OPTIONAL=true
          echo -e "${YELLOW}Review label detected on issue #${ISSUE_NUM}; allowing test failures for this task.${NC}" >&2
        fi
      fi
    fi
  fi
fi

# Helper to run a command and mark failure
run_step() {
  local title="$1"; shift
  echo -e "\n${BLUE}→ ${title}${NC}" >&2
  "$@"
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    echo -e "${RED}✗ ${title} failed (exit $rc)${NC}" >&2
    FAIL=1
  else
    echo -e "${GREEN}✓ ${title} passed${NC}" >&2
  fi
  return $rc
}

# 1) Lint check (reuse smart-lint; interpret its output)
lint_check() {
  if [[ -x "$SCRIPT_DIR/smart-lint.sh" ]]; then
    # Capture output because smart-lint exits 2 even on success
    local out
    out=$("$SCRIPT_DIR/smart-lint.sh" --fast 2>&1)
    local rc=$?
    echo "$out" | tee -a "$LINT_LOG" >&2
    # Determine pass/fail by message content
    if echo "$out" | grep -q "🛑 FAILED"; then
      return 2
    fi
    if echo "$out" | grep -q "Found .* issue(s)"; then
      return 2
    fi
    # Treat everything else as success
    echo -e "\nLint log saved to: ${LINT_LOG}" >&2
    return 0
  fi
  # No linter available; don't fail
  echo "smart-lint.sh not found; skipping lint gate" >&2
  return 0
}

# 2) Test check (project-aware)
test_check() {
  # Prefer Makefile test target
  if [[ -f Makefile ]] && grep -qE "^test:" Makefile; then
    make test 2>&1 | tee -a "$TEST_LOG"
    local rc=${PIPESTATUS[0]}
    [[ $rc -eq 0 ]] && echo -e "\nTest log saved to: ${TEST_LOG}" >&2
    return $rc
  fi

  # Python
  if command -v pytest >/dev/null 2>&1 && [[ -d tests || -n "$(find . -maxdepth 3 -name 'test_*.py' -o -name '*_test.py' -print -quit 2>/dev/null)" ]]; then
    pytest -q 2>&1 | tee -a "$TEST_LOG"
    local rc=${PIPESTATUS[0]}
    [[ $rc -eq 0 ]] && echo -e "\nTest log saved to: ${TEST_LOG}" >&2
    return $rc
  fi

  # Go
  if command -v go >/dev/null 2>&1 && [[ -f go.mod ]]; then
    go test ./... 2>&1 | tee -a "$TEST_LOG"
    local rc=${PIPESTATUS[0]}
    [[ $rc -eq 0 ]] && echo -e "\nTest log saved to: ${TEST_LOG}" >&2
    return $rc
  fi

  # Rust
  if command -v cargo >/dev/null 2>&1 && [[ -f Cargo.toml ]]; then
    cargo test --quiet 2>&1 | tee -a "$TEST_LOG"
    local rc=${PIPESTATUS[0]}
    [[ $rc -eq 0 ]] && echo -e "\nTest log saved to: ${TEST_LOG}" >&2
    return $rc
  fi

  # Node
  if command -v npm >/dev/null 2>&1 && [[ -f package.json ]]; then
    if command -v jq >/dev/null 2>&1; then
      if jq -er '.scripts.test // empty' package.json >/dev/null 2>&1; then
        npm test --silent 2>&1 | tee -a "$TEST_LOG"
        local rc=${PIPESTATUS[0]}
        [[ $rc -eq 0 ]] && echo -e "\nTest log saved to: ${TEST_LOG}" >&2
        return $rc
      fi
    else
      # Fallback: naive grep to detect a test script
      if grep -q '"test"[[:space:]]*:' package.json; then
        npm test --silent 2>&1 | tee -a "$TEST_LOG"
        local rc=${PIPESTATUS[0]}
        [[ $rc -eq 0 ]] && echo -e "\nTest log saved to: ${TEST_LOG}" >&2
        return $rc
      fi
    fi
  fi

  echo "No recognizable test runner found; skipping test gate" >&2
  return 0
}

# 3) Basic evidence hints (non-blocking)
evidence_hint() {
  # Encourage evidence without blocking
  if [[ ! -d logs ]]; then
    echo -e "${YELLOW}Hint:${NC} create a logs/ folder and capture test outputs for traceability." >&2
  fi
}

readme_check() {
  local warn=0
  # Check for README presence
  if [[ ! -f README.md && ! -f README ]]; then
    echo -e "${YELLOW}Warning:${NC} README.md is missing. Consider adding/updating README before closing the task." >&2
    warn=1
  fi

  # If in a git repo, check if non-doc files changed without README updates
  if command -v git >/dev/null 2>&1 && [[ -d .git ]]; then
    # Gather changed files (staged + unstaged)
    local changed
    changed=$(git status --porcelain 2>/dev/null | awk '{print $2}')
    if [[ -n "$changed" ]]; then
      # Filter out docs and README
      local non_docs
      non_docs=$(echo "$changed" | grep -Ev '^(README(\.md)?|docs/|logs/|\.claude/|\.gitignore)$' || true)
      local readme_changed
      readme_changed=$(echo "$changed" | grep -E '^README(\.md)?$' || true)
      if [[ -n "$non_docs" && -z "$readme_changed" ]]; then
        echo -e "${YELLOW}Notice:${NC} Code or config changed but README.md not updated. Ensure README reflects behavior/usage if applicable." >&2
        warn=1
      fi
    fi
  fi

  return $warn
}

impact_map_check() {
  # Require an impact map for new files to ensure integration thinking
  [[ -d .git ]] || return 0
  # Collect new files (added or untracked)
  mapfile -t new_files < <(git status --porcelain 2>/dev/null | awk '$1=="A" || $1=="??" {print $2}')
  # Filter out non-code/doc assets
  filtered=()
  for f in "${new_files[@]}"; do
    [[ -z "$f" ]] && continue
    case "$f" in
      README|README.md|docs/*|logs/*|.claude/*|.github/*|assets/*|.gitignore)
        continue ;;
      *) filtered+=("$f") ;;
    esac
  done
  if [[ ${#filtered[@]} -eq 0 ]]; then
    return 0
  fi

  # Overrides
  if [[ -f .claude/allow-missing-impact ]]; then
    echo -e "${YELLOW}Override:${NC} .claude/allow-missing-impact present; skipping impact map requirement." >&2
    IMPACT_OK=0
    return 0
  fi

  if ! command -v jq >/dev/null 2>&1; then
    echo -e "${RED}Blocking:${NC} jq is required to validate .claude/impact.json for new files." >&2
    echo -e "${YELLOW}Action:${NC} install jq or add .claude/allow-missing-impact to override (not recommended)." >&2
    return 2
  fi
  if [[ ! -f .claude/impact.json ]]; then
    echo -e "${RED}Blocking:${NC} .claude/impact.json missing but new files detected: ${#filtered[@]}" >&2
    printf 'Example schema:\n%s\n' '{"integrations":[{"new":"path/to/new.py","integrates_with":["existing/module.py"]}]}' >&2
    return 2
  fi
  # Validate the impact map
  local missing=0
  for nf in "${filtered[@]}"; do
    local count
    count=$(jq --arg nf "$nf" '[.integrations[]? | select(.new==$nf and (.integrates_with|length>0))] | length' .claude/impact.json 2>/dev/null || echo 0)
    if [[ "$count" -eq 0 ]]; then
      echo -e "${RED}Missing impact entry:${NC} $nf (add to .claude/impact.json with integrates_with)" >&2
      missing=$((missing+1))
    fi
  done
  if [[ $missing -gt 0 ]]; then
    return 2
  fi
  return 0
}

change_pattern_check() {
  [[ -d .git ]] || return 0
  local added=0 modified=0 deleted=0 untracked=0
  while read -r status file; do
    case "$status" in
      A*|*A) added=$((added+1)) ;;
      M*|*M) modified=$((modified+1)) ;;
      D*|*D) deleted=$((deleted+1)) ;;
      \?\?) untracked=$((untracked+1)) ;;
    esac
  done < <(git status --porcelain 2>/dev/null || true)

  local new_total=$((added+untracked))
  if [[ $new_total -ge 3 && $modified -eq 0 ]]; then
    ADDITIVE_ONLY=1
    echo -e "${YELLOW}Notice:${NC} Detected ${new_total} new files with no modifications to existing files." >&2
    echo -e "${YELLOW}Risk:${NC} additive-only changes can indicate bypassing integration or duplication." >&2
    if [[ ! -f .claude/allow-additive-fix ]]; then
      echo -e "${RED}Blocking:${NC} create .claude/allow-additive-fix to acknowledge additive-only approach, or modify existing code to integrate new modules." >&2
      return 2
    else
      echo -e "${YELLOW}Override:${NC} .claude/allow-additive-fix present; proceeding despite additive-only changes (auto-close disabled)." >&2
    fi
  fi
  return 0
}

run_step "Lint gate" lint_check || true
if ! run_step "Test gate" test_check; then
  if [[ "$TEST_GATE_OPTIONAL" == true ]]; then
    echo -e "${YELLOW}Test failures allowed for this task mode (review).${NC}" >&2
  else
    true
  fi
fi
evidence_hint
readme_check || true
if ! change_pattern_check; then
  FAIL=1
fi
if ! impact_map_check; then
  FAIL=1
fi

# Loop-prevention state handling
STATE_DIR=".claude"
STATE_FILE="${STATE_DIR}/completion-guard.state"
mkdir -p "$STATE_DIR"
CONSEC_FAILS=0
FAIL_REASON=""
# Max retries configuration: env > file > default(3)
MAX_RETRIES=${CLAUDE_GUARD_MAX_RETRIES:-}
if [[ -z "$MAX_RETRIES" && -f .claude/guard-max-retries ]]; then
  MAX_RETRIES="$(tr -d '\r' < .claude/guard-max-retries | head -n1 | xargs)"
fi
case "$MAX_RETRIES" in
  '' ) MAX_RETRIES=3 ;;
  * ) if ! echo "$MAX_RETRIES" | grep -qE '^[0-9]+$'; then MAX_RETRIES=3; fi ;;
esac
if [[ -f "$STATE_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$STATE_FILE" 2>/dev/null || true
fi

if [[ $FAIL -ne 0 ]]; then
  echo -e "\n${RED}❌ DoD not met: fix failing gates before declaring done.${NC}" >&2
  # Track consecutive failures and reason
  if [[ "$TEST_GATE_OPTIONAL" == true ]]; then
    FAIL_REASON="lint_or_other"
  else
    FAIL_REASON="tests_failing"
  fi
  CONSEC_FAILS=$((CONSEC_FAILS+1))
  printf 'CONSEC_FAILS=%s\nFAIL_REASON=%s\n' "$CONSEC_FAILS" "$FAIL_REASON" > "$STATE_FILE"
  # Update GitHub issue with status (non-blocking)
  if [[ -x "$SCRIPT_DIR/github-ops.sh" ]]; then
    STATUS="Automated gates failed. Please address lint/tests.\n\nLogs:\n- Lint: ${LINT_LOG}\n- Tests: ${TEST_LOG}"
    "$SCRIPT_DIR/github-ops.sh" comment "$STATUS" || true
  fi
  # If we failed MAX_RETRIES times in a row, document and allow moving on
  if [[ "$CONSEC_FAILS" -ge "$MAX_RETRIES" ]]; then
    echo -e "${YELLOW}Repeated failures detected (${CONSEC_FAILS}). Documenting and allowing completion to avoid loops.${NC}" >&2
    if [[ -x "$SCRIPT_DIR/github-ops.sh" ]]; then
      SUMMARY=$(cat <<EOF
Loop prevention engaged after ${CONSEC_FAILS} failed completion checks. Reason: ${FAIL_REASON}.

Evidence logs:
- Lint: ${LINT_LOG}
- Tests: ${TEST_LOG}

Next steps suggested:
- Resolve remaining failures or enable review-mode overrides for review-only tasks.
EOF
)
      "$SCRIPT_DIR/github-ops.sh" comment "$SUMMARY" || true
    fi
    # Reset counter after allowing completion so next cycle starts fresh
    printf 'CONSEC_FAILS=0\nFAIL_REASON=\n' > "$STATE_FILE"
    exit 0
  fi
  # Otherwise keep session running
  exit 2
fi

echo -e "\n${GREEN}All completion gates passed. Safe to conclude.${NC}" >&2
# Reset loop-prevention state on success
printf 'CONSEC_FAILS=0\nFAIL_REASON=\n' > "$STATE_FILE"
# Post success status to GitHub and optionally close the issue
if [[ -x "$SCRIPT_DIR/github-ops.sh" ]]; then
  SUCCESS_MSG="All completion gates passed. Evidence logs:\n- Lint: ${LINT_LOG}\n- Tests: ${TEST_LOG}"
  "$SCRIPT_DIR/github-ops.sh" comment "$SUCCESS_MSG" || true
  if [[ "$TEST_GATE_OPTIONAL" != true && "$ADDITIVE_ONLY" -ne 1 && "$IMPACT_OK" -eq 1 && "${CLAUDE_GH_AUTO_CLOSE:-true}" == "true" ]]; then
    "$SCRIPT_DIR/github-ops.sh" close "Closing automatically after successful gates." || true
  fi
fi
# Exit 0 to allow normal completion
exit 0
