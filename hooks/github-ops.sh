#!/usr/bin/env bash
# github-ops.sh - Lightweight GitHub issue automation for Claude hooks

set +euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR=".claude"
ISSUE_FILE="${STATE_DIR}/.current_issue"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

is_github_repo() {
  [[ -d .git ]] || return 1
  local url
  url=$(git remote get-url origin 2>/dev/null || true)
  [[ "$url" == *github.com* ]]
}

have_gh() {
  command -v gh >/dev/null 2>&1
}

ensure_state_dir() {
  mkdir -p "$STATE_DIR" || true
}

current_branch() {
  git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "detached"
}

title_from_progress() {
  # Extract first unchecked item from PROGRESS.md under "## Current Task"
  if [[ -f PROGRESS.md ]]; then
    awk '/^## Current Task/{flag=1; next} /^## /{flag=0} flag && /- \[ \]/{sub("- \\[ \\] ", ""); print; exit}' PROGRESS.md
  fi
}

get_issue_title() {
  # Priority: env -> PROGRESS.md -> branch
  if [[ -n "${CLAUDE_TASK_TITLE:-}" ]]; then echo "$CLAUDE_TASK_TITLE"; return; fi
  local t
  t=$(title_from_progress)
  if [[ -n "$t" ]]; then echo "$t"; return; fi
  echo "Task: $(current_branch)"
}

issue_exists_by_number() {
  local num="$1"
  [[ -z "$num" ]] && return 1
  gh issue view "$num" >/dev/null 2>&1
}

find_issue_by_title() {
  local title="$1"
  gh issue list --limit 100 --search "$title in:title" --json number,title,state \
    --jq ".[] | select(.title==\"$title\") | .number" 2>/dev/null | head -n1
}

create_issue() {
  local title="$1"; shift
  local body="$1"; shift || true
  local out
  if ! out=$(gh issue create -t "$title" -b "$body" --json number --jq .number 2>&1); then
    echo "gh issue create failed: $out" >&2
    return 1
  fi
  echo "$out"
}

comment_issue() {
  local num="$1"; shift
  local body="$1"; shift
  gh issue comment "$num" -b "$body" >/dev/null 2>&1
}

close_issue() {
  local num="$1"; shift
  local body="$1"; shift || true
  if [[ -n "$body" ]]; then
    gh issue close "$num" -c "$body" >/dev/null 2>&1
  else
    gh issue close "$num" >/dev/null 2>&1
  fi
}

cmd_ensure() {
  is_github_repo || return 0
  have_gh || { echo "gh not found; skipping GitHub ops" >&2; return 0; }
  gh auth status >/dev/null 2>&1 || { echo "gh not authenticated; skipping" >&2; return 0; }
  ensure_state_dir

  local title body num
  title="$(get_issue_title)"
  if [[ -f "$ISSUE_FILE" ]]; then
    num=$(cat "$ISSUE_FILE" 2>/dev/null)
    if issue_exists_by_number "$num"; then
      echo "Using existing issue #$num ($title)" >&2
      return 0
    fi
  fi

  num="$(find_issue_by_title "$title")"
  if [[ -z "$num" ]]; then
    body=$(cat <<'EOT'
This issue was created automatically to track the current task.

Acceptance Criteria (edit as needed):
- [ ] Clear, testable outcomes defined
- [ ] Implementation details sketched (modules/files impacted)
- [ ] Tests identified (unit/integration) or added
- [ ] Documentation updated if behavior/API changes

Suggested Tests:
- Unit tests for changed modules
- Integration test covering end-to-end behavior
- Negative test for failure modes
EOT
)
    num="$(create_issue "$title" "$body")"
    if [[ -n "$num" ]]; then
      echo -e "${GREEN}Opened GitHub issue #$num: $title${NC}" >&2
      echo "$num" > "$ISSUE_FILE"
    else
      echo -e "${YELLOW}Could not create issue; continuing without${NC}" >&2
    fi
  else
    echo "$num" > "$ISSUE_FILE"
    echo -e "${GREEN}Linked to existing GitHub issue #$num${NC}" >&2
  fi
}

cmd_comment() {
  is_github_repo || return 0
  have_gh || return 0
  gh auth status >/dev/null 2>&1 || return 0
  [[ -f "$ISSUE_FILE" ]] || return 0
  local num body
  num=$(cat "$ISSUE_FILE")
  body="$1"
  [[ -z "$body" ]] && return 0
  comment_issue "$num" "$body"
}

cmd_close() {
  is_github_repo || return 0
  have_gh || return 0
  gh auth status >/dev/null 2>&1 || return 0
  [[ -f "$ISSUE_FILE" ]] || return 0
  local num
  num=$(cat "$ISSUE_FILE")
  close_issue "$num" "$1"
}

case "${1:-}" in
  ensure) shift; cmd_ensure "$@" ;;
  comment) shift; cmd_comment "$@" ;;
  close) shift; cmd_close "$@" ;;
  *) echo "Usage: $0 {ensure|comment|close}" >&2; exit 0 ;;
esac

exit 0
