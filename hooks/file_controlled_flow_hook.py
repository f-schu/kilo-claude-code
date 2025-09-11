#!/usr/bin/env python3
"""
Minimal File-Controlled Flow Hook - Ultra token-efficient

Behavior
- Looks for a file named `flow.txt` to decide whether to block completion.
- If the file contains "0": allow completion (exit 0).
- If the file contains "1" (or is missing/invalid): block completion by sleeping and exiting with code 2.

Configuration (env vars)
- CLAUDE_PROJECT_DIR: optional path to the active project (default: ".").
- FLOW_HOOK_SLEEP_SECONDS: optional int sleep before blocking (default 30).
- FLOW_HOOK_DEBUG: set to "1" to enable debug logs to stderr.
"""
import os
import sys
import time
from typing import List


def _env_bool(name: str, default: bool = False) -> bool:
    v = os.environ.get(name)
    if v is None:
        return default
    return v.strip().lower() in {"1", "true", "yes", "on"}


def main() -> int:
    sleep_seconds = int(os.environ.get("FLOW_HOOK_SLEEP_SECONDS", "30"))
    debug = _env_bool("FLOW_HOOK_DEBUG", False)

    project_dir = os.environ.get("CLAUDE_PROJECT_DIR", ".")
    cwd = os.getcwd()

    candidates: List[str] = [
        os.path.join(project_dir, "flow.txt"),
        os.path.join(cwd, "flow.txt"),
        "flow.txt",
        os.path.abspath("flow.txt"),
    ]

    if debug:
        print(f"DEBUG: CLAUDE_PROJECT_DIR={project_dir}", file=sys.stderr)
        print(f"DEBUG: cwd={cwd}", file=sys.stderr)
        print(f"DEBUG: candidates={candidates}", file=sys.stderr)

    flow_path = None
    for path in candidates:
        if os.path.exists(path):
            flow_path = path
            if debug:
                print(f"DEBUG: found flow.txt at: {path}", file=sys.stderr)
            break

    # Default: block (flow enabled) if no file
    flow_enabled = True

    if flow_path is None:
        if debug:
            print("DEBUG: no flow.txt found; defaulting to enabled (block)", file=sys.stderr)
    else:
        try:
            with open(flow_path, "r", encoding="utf-8") as f:
                raw = f.read()
            content = raw.strip()
            if debug:
                print(f"DEBUG: file={flow_path}", file=sys.stderr)
                print(f"DEBUG: raw='{raw}' len={len(raw)}", file=sys.stderr)
                print(f"DEBUG: stripped='{content}'", file=sys.stderr)

            if content == "0":
                if debug:
                    print("DEBUG: content==0 -> allow completion", file=sys.stderr)
                return 0
            elif content == "1":
                if debug:
                    print("DEBUG: content==1 -> block completion", file=sys.stderr)
                flow_enabled = True
            else:
                if debug:
                    print("DEBUG: unexpected content -> default to enabled (block)", file=sys.stderr)
        except Exception as e:
            if debug:
                print(f"DEBUG: error reading file: {type(e).__name__}: {e}", file=sys.stderr)
            # On error default to enabled (block)
            pass

    # If here, we block completion: sleep then exit 2 so Claude continues the session
    if debug:
        print(f"DEBUG: flow enabled; sleeping {sleep_seconds}s then exit 2", file=sys.stderr)
    print(f"flow=1; sleep({sleep_seconds})", file=sys.stderr)
    time.sleep(sleep_seconds)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())

