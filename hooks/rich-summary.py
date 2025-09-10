#!/usr/bin/env python3
"""
rich-summary.py

Render a short, pretty summary panel using Rich when available.
Reads a JSON object from stdin with optional keys:
{
  "title": "...",
  "style": "green|red|yellow|blue|magenta|cyan",
  "fields": [["Key","Value"], ...],
  "notes": ["line 1", "line 2"]
}

If Rich is not installed, this script exits silently (0) to avoid breaking hooks.
"""
import sys
import json

try:
    from rich.console import Console
    from rich.panel import Panel
    from rich.table import Table
    from rich.markdown import Markdown
except Exception:
    # No rich available; do nothing
    sys.exit(0)


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0

    title = payload.get("title", "Summary")
    style = payload.get("style", "blue")
    fields = payload.get("fields", [])
    notes = payload.get("notes", [])

    console = Console()

    table = None
    if fields:
        table = Table(show_header=False, box=None, pad_edge=False)
        table.add_column(style="bold")
        table.add_column()
        for k, v in fields:
            table.add_row(str(k), str(v))

    text = "\n".join(f"• {n}" for n in notes) if notes else ""

    renderable = []
    if table is not None:
        renderable.append(table)
    if text:
        try:
            renderable.append(Markdown(text))
        except Exception:
            renderable.append(text)

    console.print(Panel.fit(*renderable, title=title, border_style=style))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

