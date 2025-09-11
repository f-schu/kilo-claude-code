#!/usr/bin/env python3
import argparse
import os
import sys
from pathlib import Path

# Ensure repo root (parent of scripts/) is importable
SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from apogeemind.db.duckdb_manager import DuckDBManager


def main() -> int:
    ap = argparse.ArgumentParser(description="ApogeeMind health: print DB path and counts")
    ap.add_argument("--to-context", action="store_true", help="Print as <system-reminder> to stdout for context")
    args = ap.parse_args()

    project_dir = Path.cwd()
    db_path = os.environ.get("APOGEEMIND_DUCKDB_PATH", str(project_dir / "apogeemind" / "apogeemind.duckdb"))
    namespace = os.environ.get("APOGEEMIND_NAMESPACE", f"code:{project_dir.name}")

    db = DuckDBManager(db_path, auto_init_schema=True)
    chats = db.execute("SELECT COUNT(*) AS c FROM chat_history WHERE namespace = ?", (namespace,)).rows[0]["c"]
    stm = db.execute("SELECT COUNT(*) AS c FROM short_term_memory WHERE namespace = ?", (namespace,)).rows[0]["c"]
    ltm = db.execute("SELECT COUNT(*) AS c FROM long_term_memory WHERE namespace = ?", (namespace,)).rows[0]["c"]

    line = f"apogeemind health: db={db_path} ns={namespace} chats={chats} stm={stm} ltm={ltm}"

    if args.to_context:
        sys.stdout.write("<system-reminder>\n")
        sys.stdout.write(line + "\n")
        sys.stdout.write("</system-reminder>\n")
    else:
        print(line, file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

