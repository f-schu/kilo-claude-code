# Claude Code Hooks

Automated code quality checks that run after Claude Code modifies files, enforcing project standards with zero tolerance for errors.

## Hooks

### `smart-lint.sh`
Intelligent project-aware linting that automatically detects language and runs appropriate checks:
- **Go**: `gofmt`, `golangci-lint` (enforces forbidden patterns like `time.Sleep`, `panic()`, `interface{}`)
- **Python**: `black`, `ruff` or `flake8`
- **JavaScript/TypeScript**: `eslint`, `prettier`
- **Rust**: `cargo fmt`, `cargo clippy`
- **Nix**: `nixpkgs-fmt`/`alejandra`, `statix`

Features:
- Detects project type automatically
- Respects project-specific Makefiles (`make lint`)
- Smart file filtering (only checks modified files)
- Fast mode available (`--fast` to skip slow checks)
- Exit code 2 means issues found - ALL must be fixed

#### Failure

```
> Edit operation feedback:
  - [~/.claude/hooks/smart-lint.sh]:
  🔍 Style Check - Validating code formatting...
  ────────────────────────────────────────────
  [INFO] Project type: go
  [INFO] Running Go formatting and linting...
  [INFO] Using Makefile targets

  ═══ Summary ═══
  ❌ Go linting failed (make lint)

  Found 1 issue(s) that MUST be fixed!
  ════════════════════════════════════════════
  ❌ ALL ISSUES ARE BLOCKING ❌
  ════════════════════════════════════════════
  Fix EVERYTHING above until all checks are ✅ GREEN

  🛑 FAILED - Fix all issues above! 🛑
  📋 NEXT STEPS:
    1. Fix the issues listed above
    2. Verify the fix by running the lint command again
    3. Continue with your original task
```
```

#### Success

```
> Task operation feedback:
  - [~/.claude/hooks/smart-lint.sh]:
  🔍 Style Check - Validating code formatting...
  ────────────────────────────────────────────
  [INFO] Project type: go
  [INFO] Running Go formatting and linting...
  [INFO] Using Makefile targets

  👉 Style clean. Continue with your task.
```
```

By `exit 2` on success and telling it to continue, we prevent Claude from stopping after it has corrected
the style issues.

### `ntfy-notifier.sh`
Push notifications via ntfy service for Claude Code events:
- Sends alerts when Claude finishes tasks
- Includes terminal context (tmux/Terminal window name) for identification
- Requires `~/.config/claude-code-ntfy/config.yaml` with topic configuration

### `plan-guard.sh`
Pre-tool-use reminder to formalize planning and agent orchestration:
- Prints a concise checklist for Task Contract, Agent Allocation, and Subagent Contracts
- Non-blocking; reinforces process without adding friction

### `completion-guard.sh`
Pre-stop gate that blocks premature completion when quality gates fail:
- Re-runs a fast lint gate (via `smart-lint.sh`) and a project-aware test gate
- Fails with exit code 2 when gates are not green (keeps the session running)
- Succeeds with exit code 0 when safe to conclude

### `github-ops.sh`
Lightweight helper for GitHub issue automation (non-blocking):
- Detects GitHub repo and `gh` CLI auth
- `ensure`: creates/links an issue for the current task (uses `PROGRESS.md` or branch name)
- `comment`: posts iteration/status comments (evidence, logs)
- `close`: closes the current issue when done
- Stores the current issue number in `.claude/.current_issue`

### `apogeemind-inject.sh` and `apogeemind-record.sh`
Local memory integration for Claude Code using the self-contained apogeemind engine:
- `apogeemind-inject.sh` (UserPromptSubmit): injects a `<system-reminder>` with relevant memories via `scripts/apogeemind_inject.py`.
- `apogeemind-record.sh` (Post-response): records the last user/assistant exchange via `scripts/apogeemind_record.py`.

See docs/instructions/memori_hooks_guide.md for setup, env vars, and troubleshooting.

### `apogeemind-init.sh` (optional)
Initialize the project-local DuckDB at `./apogeemind/apogeemind.duckdb` and print status. Register on session start if your environment supports it, or run manually once per project.

### `apogeemind-health.sh` (optional)
Print a one-line status with DB path and counts (chats/STM/LTM) after a response:
- Register as a post-response hook to verify live updates.
- Env `APOGEEMIND_HEALTH_TO_CONTEXT=1` prints as a `<system-reminder>` to context; otherwise logs to stderr.

### `file_controlled_flow_hook.py`
Minimal, file-controlled completion gate:
- Looks for `flow.txt` in the project directory (and a few fallbacks).
- If it contains `0`: allows completion immediately (exit 0).
- If it contains `1` (or missing): sleeps (default 30s) and exits 2 to block completion, keeping the session going.

Usage:
- Register under a completion/stop hook in Claude Code.
- Place `flow.txt` in your project root with `1` to stay in flow; change to `0` when you want to let Claude finish.
- Config via env:
  - `FLOW_HOOK_SLEEP_SECONDS` (default 30)
  - `FLOW_HOOK_DEBUG=1` to log details

## Installation

Automatically installed by Nix home-manager to `~/.claude/hooks/`

## Configuration

### Global Settings
Set environment variables or create project-specific `.claude-hooks-config.sh`:

```bash
CLAUDE_HOOKS_ENABLED=false      # Disable all hooks
CLAUDE_HOOKS_DEBUG=1            # Enable debug output
```

### Per-Project Settings
Create `.claude-hooks-config.sh` in your project root:

```bash
# Language-specific options
CLAUDE_HOOKS_GO_ENABLED=false
CLAUDE_HOOKS_GO_COMPLEXITY_THRESHOLD=30
CLAUDE_HOOKS_PYTHON_ENABLED=false

# See example-claude-hooks-config.sh for all options
```

### Excluding Files
Create `.claude-hooks-ignore` in your project root using gitignore syntax:

```
vendor/**
node_modules/**
*.pb.go
*_generated.go
```

Add `// claude-hooks-disable` to the top of any file to skip hooks.

## Usage

```bash
./smart-lint.sh           # Auto-runs after Claude edits
./smart-lint.sh --debug   # Debug mode
./smart-lint.sh --fast    # Skip slow checks
```

### Exit Codes
- `0`: All checks passed ✅
- `1`: General error (missing dependencies)
- `2`: Issues found - must fix ALL

## Dependencies

Hooks work best with these tools installed:
- **Go**: `golangci-lint`
- **Python**: `black`, `ruff`
- **JavaScript**: `eslint`, `prettier` 
- **Rust**: `cargo fmt`, `cargo clippy`
- **Nix**: `nixpkgs-fmt`, `alejandra`, `statix`

Hooks gracefully degrade if tools aren't installed.
