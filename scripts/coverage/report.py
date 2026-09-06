#!/usr/bin/env python3
"""Create stable categorized summaries from a Verilator coverage database."""

from __future__ import annotations

import argparse
import json
import re
from collections import defaultdict
from pathlib import Path


FIELD = re.compile(r"\x01([^\x02]+)\x02([^\x01]*)")
CATEGORIES = {
    "v_line": "Line",
    "v_branch": "Branch",
    "v_toggle": "Toggle",
    "v_user": "Property/functional",
}


def parse_database(path: Path) -> dict[str, list[dict[str, object]]]:
    points: dict[str, list[dict[str, object]]] = defaultdict(list)
    for line in path.read_text(encoding="latin-1").splitlines():
        if not line.startswith("C '"):
            continue
        fields = dict(FIELD.findall(line))
        page = fields.get("page", "unknown")
        kind = page.split("/", 1)[0]
        try:
            count = int(line.rsplit("' ", 1)[1])
        except (IndexError, ValueError):
            continue
        threshold = int(fields.get("thresh", "1"))
        points[kind].append({
            "count": count,
            "covered": count >= threshold,
            "threshold": threshold,
            "file": fields.get("f", ""),
            "line": int(fields.get("l", "0")),
            "name": fields.get("o", fields.get("comment", "")),
            "hierarchy": fields.get("h", ""),
        })
    return points


def summarize(points: dict[str, list[dict[str, object]]]) -> dict[str, object]:
    categories = []
    for kind in ("v_line", "v_branch", "v_toggle", "v_user"):
        entries = points.get(kind, [])
        covered = sum(bool(entry["covered"]) for entry in entries)
        total = len(entries)
        categories.append({
            "key": kind,
            "name": CATEGORIES[kind],
            "covered": covered,
            "total": total,
            "percent": (100.0 * covered / total) if total else None,
            "uncovered": [entry for entry in entries if not entry["covered"]],
        })
    covered = sum(int(item["covered"]) for item in categories)
    total = sum(int(item["total"]) for item in categories)
    return {
        "covered": covered,
        "total": total,
        "percent": (100.0 * covered / total) if total else None,
        "categories": categories,
    }


def render(summary: dict[str, object]) -> str:
    lines = ["Axon coverage summary", "=====================", ""]
    for item in summary["categories"]:
        percent = "N/A" if item["percent"] is None else f"{item['percent']:.2f}%"
        lines.append(
            f"{item['name']:<20} {percent:>8}  "
            f"({item['covered']}/{item['total']} points)"
        )
    lines.extend([
        "",
        f"Overall              {summary['percent']:.2f}%  "
        f"({summary['covered']}/{summary['total']} points)",
    ])
    uncovered = [
        (item["name"], point)
        for item in summary["categories"]
        for point in item["uncovered"]
    ]
    if uncovered:
        lines.extend(["", "Uncovered points", "----------------"])
        for category, point in uncovered:
            location = f"{point['file']}:{point['line']}"
            detail = point["name"] or point["hierarchy"]
            lines.append(f"{category}: {location}: {detail}")
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("database", type=Path)
    parser.add_argument("--text", required=True, type=Path)
    parser.add_argument("--json", required=True, type=Path)
    args = parser.parse_args()
    summary = summarize(parse_database(args.database))
    args.text.write_text(render(summary), encoding="utf-8")
    args.json.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(render(summary), end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
