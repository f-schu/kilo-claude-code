from typing import Any, Dict, List


class ContextBuilder:
    def __init__(self, max_chars: int = 2000, line_max: int = 240) -> None:
        self.max_chars = max_chars
        self.line_max = line_max

    def build_system_block(self, items: List[Dict[str, Any]], header_label: str = "Relevant Memories", namespace: str = "") -> str:
        header_ns = f" (namespace={namespace})" if namespace else ""
        lines = [f"--- {header_label}{header_ns} ---"]

        for it in items:
            cat = str(it.get("category_primary", "")).upper() or "CONTEXT"
            summ = str(it.get("summary", "")).strip()
            created = str(it.get("created_at", ""))
            imp = float(it.get("importance_score", 0.0))
            line = f"- [{cat}] {summ} ({created}, importance={imp:.2f})"
            if len(line) > self.line_max:
                line = line[: self.line_max - 1] + "…"
            lines.append(line)

            text = "\n".join(lines)
            if len(text) >= self.max_chars:
                break

        lines.append("--- End Memories ---")
        out = "\n".join(lines)
        return out[: self.max_chars]

