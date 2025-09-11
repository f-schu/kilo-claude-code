#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || echo "$(pwd)")"
python3 "$repo_root/scripts/memori_local_init.py"
exit 0

