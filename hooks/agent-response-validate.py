#!/usr/bin/env python3
"""
agent-response-validate.py

Validates agent "Return Format" JSON snippets embedded in agents/*.md files.
- Extracts the fenced ```json blocks under the "Return Format" section
- Parses JSON and checks for required top-level keys per agent

Usage:
  ./hooks/agent-response-validate.py            # validate all agents
  ./hooks/agent-response-validate.py agents/foo.md  # validate single agent file

Exit codes:
  0 = all good, 1 = failures found
"""
import re
import sys
import json
from pathlib import Path

AGENT_REQUIRED_KEYS = {
    "ai-ml-innovation-advisor": ["summary", "metrics", "pipeline_outline"],
    "benchmark-evaluator": ["summary", "commands", "metrics"],
    "publication-dataviz-expert": ["summary", "exports", "dimensions"],
    "scientific-evidence-validator": ["verdict", "claim", "evidence", "recommendation"],
    "tidy-python-developer": ["summary", "files_changed", "tests"],
    "genomics-database-architect": ["summary", "ddl", "queries"],
    "security-privacy-auditor": ["summary", "findings", "remediations"],
    "devops-ci-cd-engineer": ["summary", "workflows", "checks"],
    "project-planning-orchestrator": ["task_contract", "agent_allocation", "acceptance_tests"],
}

FRONT_MATTER_NAME_RE = re.compile(r"^name:\s*(?P<name>.+)$", re.IGNORECASE)


def extract_name(text: str) -> str | None:
    # Look for YAML front matter name: ... between '---' fences
    if not text.startswith("---"):
        return None
    try:
        end = text.index("\n---", 3)
        fm = text[3:end].splitlines()
        for line in fm:
            m = FRONT_MATTER_NAME_RE.search(line.strip())
            if m:
                return m.group("name").strip()
    except ValueError:
        return None
    return None


def extract_return_format_json(text: str) -> list[dict]:
    results = []
    # Find heading "Return Format" then the next fenced code block with json
    # Be flexible: multiple snippets allowed
    # Simple heuristic regex for ```json ... ``` blocks
    for m in re.finditer(r"```json\n(.*?)\n```", text, re.DOTALL | re.IGNORECASE):
        block = m.group(1).strip()
        try:
            data = json.loads(block)
            results.append(data)
        except json.JSONDecodeError as e:
            raise ValueError(f"Invalid JSON in Return Format: {e}\n{block[:200]}...")
    return results


def validate_required_keys(agent_name: str, payloads: list[dict]) -> list[str]:
    errs: list[str] = []
    required = AGENT_REQUIRED_KEYS.get(agent_name)
    if not required:
        return errs  # no schema defined; skip
    if not payloads:
        errs.append(f"{agent_name}: missing Return Format JSON block")
        return errs
    # Check first payload for required keys
    data = payloads[0]
    for key in required:
        if key not in data:
            errs.append(f"{agent_name}: missing required key '{key}' in Return Format JSON")
    return errs


def validate_file(path: Path) -> list[str]:
    text = path.read_text(encoding="utf-8")
    name = extract_name(text) or path.stem
    payloads = extract_return_format_json(text)
    return validate_required_keys(name, payloads)


def main() -> int:
    errs: list[str] = []
    targets: list[Path]
    if len(sys.argv) > 1:
        targets = [Path(p) for p in sys.argv[1:]]
    else:
        targets = list(Path("agents").glob("*.md"))
    for p in targets:
        if not p.exists():
            print(f"warn: skipping missing {p}", file=sys.stderr)
            continue
        try:
            errs.extend(validate_file(p))
        except Exception as e:
            errs.append(f"{p.name}: {e}")
    if errs:
        print("Agent Return Format validation FAILED:", file=sys.stderr)
        for e in errs:
            print(f"- {e}", file=sys.stderr)
        return 1
    print("Agent Return Format validation OK.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

