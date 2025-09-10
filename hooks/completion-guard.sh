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

# Logs
TODAY="$(date +%Y%m%d)"
RUNSTAMP="$(date +%Y%m%d_%H%M%S)"
LOG_DIR="logs/${TODAY}"
mkdir -p "$LOG_DIR"
LINT_LOG="${LOG_DIR}/completion-guard_lint_${RUNSTAMP}.log"
TEST_LOG="${LOG_DIR}/completion-guard_test_${RUNSTAMP}.log"

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

run_step "Lint gate" lint_check || true
run_step "Test gate" test_check || true
evidence_hint
readme_check || true

if [[ $FAIL -ne 0 ]]; then
  echo -e "\n${RED}❌ DoD not met: fix failing gates before declaring done.${NC}" >&2
  # Update GitHub issue with status (non-blocking)
  if [[ -x "$SCRIPT_DIR/github-ops.sh" ]]; then
    STATUS="Automated gates failed. Please address lint/tests.\n\nLogs:\n- Lint: ${LINT_LOG}\n- Tests: ${TEST_LOG}"
    "$SCRIPT_DIR/github-ops.sh" comment "$STATUS" || true
  fi
  # Exit 2 to keep the session running
  exit 2
fi

echo -e "\n${GREEN}All completion gates passed. Safe to conclude.${NC}" >&2
# Post success status to GitHub and optionally close the issue
if [[ -x "$SCRIPT_DIR/github-ops.sh" ]]; then
  SUCCESS_MSG="All completion gates passed. Evidence logs:\n- Lint: ${LINT_LOG}\n- Tests: ${TEST_LOG}"
  "$SCRIPT_DIR/github-ops.sh" comment "$SUCCESS_MSG" || true
  if [[ "${CLAUDE_GH_AUTO_CLOSE:-true}" == "true" ]]; then
    "$SCRIPT_DIR/github-ops.sh" close "Closing automatically after successful gates." || true
  fi
fi
# Exit 0 to allow normal completion
exit 0
