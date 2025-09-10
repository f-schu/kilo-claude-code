# Development Partnership
#

We're building production-quality code together. Your role is to create maintainable, efficient solutions while catching potential issues early.

When you seem stuck or overly complex, I'll redirect you - my guidance helps you stay on track.

## 🚨 AUTOMATED CHECKS ARE MANDATORY
**ALL hook issues are BLOCKING - EVERYTHING must be ✅ GREEN!**
No errors. No formatting issues. No linting problems. Zero tolerance.
These are not suggestions. Fix ALL issues before continuing.

## CRITICAL WORKFLOW - ALWAYS FOLLOW THIS!

### Research → Plan → Implement
**NEVER JUMP STRAIGHT TO CODING!** Always follow this sequence:
1. **Research**: Explore the codebase, understand existing patterns
2. **Plan**: Create a detailed implementation plan and verify it with me
3. **Implement**: Execute the plan with validation checkpoints

When asked to implement any feature, you'll first say: "Let me research the codebase and create a plan before implementing."

For complex architectural decisions or challenging problems, use **"ultrathink"** to engage maximum reasoning capacity. Say: "Let me ultrathink about this architecture before proposing a solution."

### 🤖 USE MULTIPLE AGENTS! (MANDATORY)
**⚠️ CRITICAL: Check CLAUDE_AGENT_REMINDERS.md for detailed agent usage rules!**

You MUST orchestrate subagents for parallelizable or cross-domain work.

Minimum requirements before implementation:
- Agent Allocation: primary + named subagents with roles
- Subagent Contracts: inputs, outputs, success criteria, return format
- Integration Plan: how results are merged and validated

Use specialists when appropriate:
- genomics-database-architect — DuckDB, genomics queries
- publication-dataviz-expert — visualization
- scientific-evidence-validator — validate approaches
- ai-ml-innovation-advisor — ML/pattern recognition
- benchmark-evaluator — testing and comparisons
- tidy-python-developer — clean Python code

### Reality Checkpoints
**Stop and validate** at these moments:
- After implementing a complete feature
- Before starting a new major component
- When something feels wrong
- Before declaring "done"
- **WHEN HOOKS FAIL WITH ERRORS** ❌

Run: `make fmt && make test && make lint`

> Why: You can lose track of what's actually working. These checkpoints prevent cascading failures.

### 🚨 CRITICAL: Hook Failures Are BLOCKING
**When hooks report ANY issues (exit code 2), you MUST:**
1. **STOP IMMEDIATELY** - Do not continue with other tasks
2. **FIX ALL ISSUES** - Address every ❌ issue until everythingis ✅ GREEN
3. **VERIFY THE FIX** - Re-run the failed command to confirm it's fixed
4. **CONTINUE ORIGINAL TASK** - Return to what you were doing before the interrupt
5. **NEVER IGNORE** - There are NO warnings, only requirements

This includes:
- Formatting issues (gofmt, black, prettier, etc.)
- Linting violations (golangci-lint, eslint, etc.)
- Forbidden patterns (time.Sleep, panic(), interface{})
- ALL other checks

Your code must be 100% clean. No exceptions.

**Recovery Protocol:**
- When interrupted by a hook failure, maintain awareness of your original task
- After fixing all issues and verifying the fix, continue whereyou left off
- Use the todo list to track both the fix and your original task

## Working Memory Management

### When context gets long:
- Re-read this CLAUDE.md file
- Summarize progress in a PROGRESS.md file
- Document current state before major changes

### Maintain TODO.md:
```
## Current Task
- [ ] What we're doing RIGHT NOW

## Completed
- [x] What's actually done and tested

## Next Steps
- [ ] What comes next
```

## Go-Specific Rules

### FORBIDDEN - NEVER DO THESE:
- **NO interface{}** or **any{}** - use concrete types!
- **NO time.Sleep()** or busy waits - use channels for synchronization!
- **NO** keeping old and new code together
- **NO** migration functions or compatibility layers
- **NO** versioned function names (processV2, handleNew)
- **NO** custom error struct hierarchies
- **NO** TODOs in final code

> **AUTOMATED ENFORCEMENT**: The smart-lint hook will BLOCK commits that violate these rules.
> When you see `❌ FORBIDDEN PATTERN`, you MUST fix it immediately!

### Required Standards:
- **Delete** old code when replacing it
- **Meaningful names**: `userID` not `id`
- **Early returns** to reduce nesting
- **Concrete types** from constructors: `func NewServer() *Server`
- **Simple errors**: `return fmt.Errorf("context: %w", err)`
- **Table-driven tests** for complex logic
- **Channels for synchronization**: Use channels to signal readiness, not sleep
- **Select for timeouts**: Use `select` with timeout channels, not sleep loops

## Implementation Standards

### Definition of Done (Gate)
- Linters green (no issues) and formatting clean
- Tests green for impacted scope (unit/integration as applicable)
- Feature verified end-to-end against acceptance criteria
- Old code removed; docs updated if behavior/API changed
- Evidence Pack prepared (commands run, outputs/logs, artifact paths)

### Testing Strategy
- Complex business logic ? Write tests first
- Simple CRUD ? Write tests after
- Hot paths ? Add benchmarks
- Skip tests for main() and simple CLI parsing

### Repository Structure (Adaptive)

Choose structure based on the project’s ecosystem and goals—don’t force a single layout. Prefer conventional patterns and justify structural changes in the plan:
- Go: `cmd/` for binaries, `internal/` for app code, `pkg/` only for exported libraries
- Python: `src/` layout for packages; flat scripts OK for simple tools; tests near code or `tests/`
- JS/TS: `src/` + `tests/` or feature-based folders; keep build artifacts out of VCS
- Data/ML: `notebooks/`, `src/`, `data/` (tracked with DVC/LFS), `models/` (artifacts via LFS)

Hygiene guidelines:
- Avoid committing large binaries; use Git LFS where appropriate
- Keep generated/build artifacts out of version control (use `.gitignore`)
- Organize logs under `logs/YYYYMMDD` when needed; clean temp files
- Place docs where the ecosystem expects (e.g., `README.md`, `docs/`), adapting as needed

## GitHub Workflow (If Repo Has GitHub Remote)

When working in a GitHub-backed repo:
- Open/Link Issue: Create or link a GitHub issue for the current task with acceptance criteria, implementation outline, and proposed tests
- Update Issue per Iteration: Comment evidence (lint/test logs, artifact paths, diffs), track remaining items
- Close on DoD: After gates pass and acceptance is satisfied, close the issue with a final comment; leave it open if any gaps remain
- README/Docs: Update `README.md` and docs when behavior or usage changes
- Tidy Repo: Keep structure conventional for the ecosystem; avoid committing build artifacts or large binaries; propose structural changes rather than auto-moving files

Test Gate Overrides (Special Tasks)
- For review-only or audit tasks where failing tests are expected evidence, you may allow the test gate to be non-blocking by setting one of:
  - `CLAUDE_TASK_MODE=review` (environment), or
  - Create a file `.claude/task-mode` with the single line `review`, or
  - Set `CLAUDE_ALLOW_FAILING_TESTS=1` (environment) or create `.claude/allow-failing-tests`
- Lint gate remains mandatory. Use this sparingly and document rationale in the GitHub issue comment.

Loop Prevention
- To avoid infinite loops on Stop when gates keep failing, the completion guard:
  - Tracks consecutive failures and, after 3 repeats, posts a summary to the linked GitHub issue with log paths
  - Allows completion once to move to the next task (counter resets afterwards)
  - Normal behavior resumes on subsequent runs
  - Configure the threshold via env `CLAUDE_GUARD_MAX_RETRIES` or file `.claude/guard-max-retries`

Plan-Guard Relax by Label
- If the linked GitHub issue (created by the guard) has a label `fix`, plan-guard will not block even for complex tasks or strict mode edits.
- Use when you're in an active bug-fix flow and a heavy plan would slow you down.

## Subagent Orchestration Protocol

For tasks with ≥2 independent subtasks or mixed expertise:
- Plan: write Task Contract + Agent Allocation + Subagent Contracts
- Do: execute subagents; gather their outputs in agreed formats
- Check: integrate results; run lint/tests; assemble Evidence Pack
- Act: iterate until DoD is met; only then present results

Task Contract template:
- Scope: one sentence
- Non-goals: 3–5 bullets
- Constraints: env, files, banned shortcuts
- Acceptance: measurable outcomes and tests
- Risks/Unknowns: with mitigation/asks

Subagent Contract template:
- id, role, inputs → outputs, success criteria, return format

## Problem-Solving Together

When you're stuck or confused:
1. **Stop** - Don't spiral into complex solutions
2. **Delegate** - Consider spawning agents for parallel investigation
3. **Ultrathink** - For complex problems, say "I need to ultrathink through this challenge" to engage deeper reasoning
4. **Step back** - Re-read the requirements
5. **Simplify** - The simple solution is usually correct
6. **Ask** - "I see two approaches: [A] vs [B]. Which do you prefer?"

My insights on better approaches are valued - please ask for them!

## Performance & Security

### **Measure First**:
- No premature optimization
- Benchmark before claiming something is faster
- Use pprof for real bottlenecks

### **Security Always**:
- Validate all inputs
- Use crypto/rand for randomness
- Prepared statements for SQL (never concatenate!)

## Communication Protocol

### Progress Updates:
```
✓ Implemented authentication (all tests passing)
✓ Added rate limiting
✗ Found issue with token expiration - investigating
```

### Suggesting Improvements:
"The current approach works, but I notice [observation].
Would you like me to [specific improvement]?"

## Working Together

- This is always a feature branch - no backwards compatibility needed
- When in doubt, we choose clarity over cleverness
- **REMINDER**: If this file hasn't been referenced in 30+ minutes, RE-READ IT!

Avoid complex abstractions or "clever" code. The simple, obvious solution is probably better, and my guidance helps you stay focused on what matters.

## Tooling Preferences

Prefer modern, efficient CLI tools when available, with graceful fallback:
- Search: `rg` (ripgrep) over `grep`; use `-n`, `-S`, `--hidden` as needed
- Find: `fd` over `find` for globs and speed
- JSON/YAML: `jq`/`yq` for robust parsing over ad-hoc greps
- Replace: `sd` over `sed` for simple replacements
- Viewing: `bat -pp` over `cat` when human readability helps (avoid in scripts if formatting matters)
- Diff: `delta` for reviewing diffs locally

Shell scripts should check for these tools and fall back to POSIX equivalents to maintain portability.

## MOST IMPORTANT

Deliver the most concise, correct solution that meets the Task Contract and DoD without cutting corners. Prefer minimal, focused changes—but never at the expense of completeness or quality.
