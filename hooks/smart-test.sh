#!/usr/bin/env python3
# smart-test.py - Automatically run tests for files edited by an AI assistant
#
# SYNOPSIS
#   PostToolUse hook that runs relevant tests when files are edited
#
# DESCRIPTION
#   When an AI assistant edits a file, this hook intelligently runs associated tests:
#   - Focused tests for the specific file
#   - Package-level tests (with optional race detection for Go)
#   - Full project tests (optional)
#   - Integration tests (if available)
#   - Configurable per-project via a configuration file (e.g., .claude-hooks-config.py)
#
# CONFIGURATION
#   CLAUDE_HOOKS_TEST_ON_EDIT - Enable/disable (default: "true")
#   CLAUDE_HOOKS_TEST_MODES - Comma-separated: focused,package,all,integration
#   CLAUDE_HOOKS_ENABLE_RACE - Enable race detection for Go (default: "true")
#   CLAUDE_HOOKS_FAIL_ON_MISSING_TESTS - Fail if test file missing (default: "false")

import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple

# ANSI color codes
BLUE = "\033[94m"
GREEN = "\033[92m"
RED = "\033[91m"
YELLOW = "\033[93m"
NC = "\033[0m"  # No Color

# Global error list
errors: List[str] = []


def add_error(message: str):
    """Adds an error message to the global list."""
    errors.append(message)


def log_success(message: str):
    """Logs a success message to stderr."""
    print(f"{GREEN}✅ {message}{NC}", file=sys.stderr)


def print_test_header():
    """Prints a consistent header for the test output."""
    print(f"{BLUE}--- Running Automated Tests ---{NC}", file=sys.stderr)


def exit_with_test_failure(file_path: str):
    """Prints a failure message and exits with an error code."""
    print(f"\n{RED}❌ Tests failed for {file_path}.{NC}", file=sys.stderr)
    print(f"{YELLOW}Review the output above to fix the issues.{NC}", file=sys.stderr)
    if errors:
        print(f"\n{RED}Summary of errors:{NC}", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
    sys.exit(1)


def exit_with_success_message(message: str):
    """Prints a success message and exits cleanly."""
    print(f"\n{GREEN}🎉 {message}{NC}", file=sys.stderr)
    sys.exit(0)


def load_project_config():
    """
    Loads project-specific configuration by executing a config file.
    (This is a placeholder for more sophisticated config loading).
    """
    config_file = Path(".claude-hooks-config.py")
    if config_file.is_file():
        try:
            with open(config_file, "r") as f:
                exec(f.read(), globals())
            if os.environ.get("CLAUDE_HOOKS_DEBUG", "0") == "1":
                print(
                    f"DEBUG: Loaded project config from {config_file}", file=sys.stderr
                )
        except Exception as e:
            print(
                f"{YELLOW}⚠️  Warning: Could not load project config {config_file}: {e}{NC}",
                file=sys.stderr,
            )


class Config:
    """Manages configuration settings."""

    def __init__(self):
        self.test_on_edit = (
            os.environ.get("CLAUDE_HOOKS_TEST_ON_EDIT", "true").lower() == "true"
        )
        self.test_modes = os.environ.get(
            "CLAUDE_HOOKS_TEST_MODES", "focused,package"
        ).split(",")
        self.enable_race = (
            os.environ.get("CLAUDE_HOOKS_ENABLE_RACE", "true").lower() == "true"
        )
        self.fail_on_missing_tests = (
            os.environ.get("CLAUDE_HOOKS_FAIL_ON_MISSING_TESTS", "false").lower()
            == "true"
        )
        self.test_verbose = (
            os.environ.get("CLAUDE_HOOKS_TEST_VERBOSE", "false").lower() == "true"
        )
        self.debug = os.environ.get("CLAUDE_HOOKS_DEBUG", "0") == "1"


def get_go_test_command(config: Config) -> List[str]:
    """Determines the appropriate Go test command."""
    base_cmd = []
    if shutil.which("gotestsum"):
        base_cmd = ["gotestsum", "--format", "dots", "--"]
        if config.debug:
            print(f"DEBUG: Found gotestsum at {shutil.which('gotestsum')}", file=sys.stderr)
    else:
        base_cmd = ["go", "test", "-v"]
        if config.debug:
            print("DEBUG: gotestsum not found, using go test", file=sys.stderr)

    if config.enable_race:
        base_cmd.append("-race")

    if config.debug:
        print(f"DEBUG: Go test command: {' '.join(base_cmd)}", file=sys.stderr)

    return base_cmd


def should_skip_test_requirement(file_path: str) -> bool:
    """Checks if a file should be exempt from requiring a test."""
    p = Path(file_path)
    base = p.name
    dir_str = str(p.parent)

    skip_patterns = [
        "main.go",
        "doc.go",
        "*_generated.go",
        "*_string.go",
        "*.pb.go",
        "*.pb.gw.go",
        "bindata.go",
    ]

    for pattern in skip_patterns:
        if p.match(pattern):
            return True

    skip_dirs_regex = re.compile(
        r"/(vendor|testdata|examples|cmd/[^/]+|gen|generated|\.gen)(/|$)"
    )
    if skip_dirs_regex.search(dir_str):
        return True

    if base.endswith(("_test.go", "_test.py", ".test.js", ".spec.js", ".test.ts", ".spec.ts")):
        return True

    return False

def format_test_output(output: str, test_type: str) -> str:
    """Formats the test output for display."""
    if not output:
        return "(no output captured)"
    # For now, just return the full output.
    return output

def run_command(cmd: List[str]) -> Tuple[bool, str]:
    """Runs a command and returns success status and output."""
    try:
        process = subprocess.run(
            cmd, capture_output=True, text=True, check=False
        )
        output = process.stdout + process.stderr
        return process.returncode == 0, output
    except FileNotFoundError:
        return False, f"Command not found: {cmd[0]}"
    except Exception as e:
        return False, f"An error occurred: {e}"

def run_python_tests(file_path: str, config: Config) -> int:
    """Runs tests for a given Python file."""
    p = Path(file_path)
    dir_path = p.parent
    base_name = p.stem.replace("_test", "").replace("test_", "")

    # If this IS a test file, run it directly
    if p.name.startswith("test_") or p.name.endswith("_test.py"):
        print(f"{BLUE}🧪 Running test file directly: {file_path}{NC}", file=sys.stderr)
        cmd = ["pytest", "-xvs", file_path] if shutil.which("pytest") else ["python", "-m", "unittest", file_path]
        success, output = run_command(cmd)
        if not success:
            print(f"{RED}❌ Tests failed in {file_path}{NC}", file=sys.stderr)
            print(f"\n{RED}Failed test output:{NC}\n{output}", file=sys.stderr)
            return 1
        print(f"{GREEN}✅ Tests passed in {file_path}{NC}", file=sys.stderr)
        return 0

    # Find corresponding test file
    test_candidates = [
        dir_path / f"test_{base_name}.py",
        dir_path / f"{base_name}_test.py",
        dir_path / "tests" / f"test_{base_name}.py",
        dir_path.parent / "tests" / f"test_{base_name}.py",
    ]
    test_file = next((f for f in test_candidates if f.is_file()), None)

    require_tests = not should_skip_test_requirement(file_path)
    tests_run = 0
    failed = 0

    for mode in config.test_modes:
        if failed: break
        mode = mode.strip()
        if mode == "focused":
            if test_file:
                print(f"{BLUE}🧪 Running focused tests for {base_name}...{NC}", file=sys.stderr)
                tests_run += 1
                cmd = ["pytest", "-xvs", str(test_file)]
                success, output = run_command(cmd)
                if not success:
                    failed = 1
                    print(f"{RED}❌ Focused tests failed for {base_name}{NC}", file=sys.stderr)
                    print(f"\n{RED}Failed test output:{NC}\n{output}", file=sys.stderr)
                    add_error(f"Focused tests failed for {base_name}")
            elif require_tests:
                print(f"{RED}❌ Missing required test file for: {file_path}{NC}", file=sys.stderr)
                add_error(f"Missing required test file for: {file_path}")
                return 2
        elif mode == "package":
            print(f"{BLUE}📦 Running package tests in {dir_path}...{NC}", file=sys.stderr)
            tests_run += 1
            cmd = ["pytest", "-xvs", str(dir_path)]
            if shutil.which("pytest"):
                success, output = run_command(cmd)
                if not success:
                    failed = 1
                    print(f"{RED}❌ Package tests failed in {dir_path}{NC}", file=sys.stderr)
                    print(f"\n{RED}Failed test output:{NC}\n{output}", file=sys.stderr)
                    add_error(f"Package tests failed in {dir_path}")

    if tests_run == 0 and require_tests and not test_file:
        print(f"{RED}❌ No tests found for {file_path} (tests required){NC}", file=sys.stderr)
        add_error(f"No tests found for {file_path} (tests required)")
        return 2
    elif failed == 0 and tests_run > 0:
        log_success(f"All tests passed for {file_path}")

    return failed

def main():
    """Main execution logic."""
    if not sys.stdin.isatty():
        input_json = sys.stdin.read()
        try:
            data = json.loads(input_json)
            tool_name = data.get("tool_name", "")
            if tool_name not in ["Edit", "Write", "MultiEdit"]:
                sys.exit(0)

            tool_input = data.get("tool_input", {})
            file_path = tool_input.get("file_path", "")
            if not file_path:
                sys.exit(0)
        except json.JSONDecodeError:
            file_path = "./..." # Fallback for non-json input
    else:
        # CLI mode
        file_path = "./..." if len(sys.argv) == 1 else sys.argv[1]


    load_project_config()
    config = Config()

    if not config.test_on_edit:
        if config.debug:
            print("DEBUG: Test on edit disabled, exiting.", file=sys.stderr)
        sys.exit(0)

    print_test_header()

    failed = 0
    if file_path.endswith(".py"):
        failed = run_python_tests(file_path, config)
    # NOTE: Go and JS/TS runners would be similarly implemented.
    # To keep this example focused, only the Python runner is fully converted.
    # elif file_path.endswith((".js", ".jsx", ".ts", ".tsx")):
    #     failed = run_javascript_tests(file_path, config)
    # elif file_path.endswith(".go") or file_path == "./...":
    #     failed = run_go_tests(file_path, config)
    else:
        if config.test_verbose:
            print(f"{YELLOW}⚠️  No test runner for file type: {file_path}{NC}", file=sys.stderr)
        sys.exit(0)

    if failed:
        exit_with_test_failure(file_path)
    else:
        exit_with_success_message("Tests pass. Continue with your task.")

if __name__ == "__main__":
    main()
