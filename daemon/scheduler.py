#!/usr/bin/env python3
"""scheduler — CONSOLIDATION_DAEMON §6/§7.6 (prioritized replay).

Queues bundles by the summed surprise of their UNCONSUMED episodes — members
not yet claimed as children by any active vault note. Consumption is derived
from the vault itself (no separate state file to lose: derive, don't
remember — the platform rule applies here too).

Usage: scheduler.py <episodes-dir> <vault-root>
Read-only. Output: the queue, noisiest first; consumed bundles drop out.
"""

import json
import re
import subprocess
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} <episodes-dir> <vault-root>", file=sys.stderr)
        return 2
    episodes_dir, vault = sys.argv[1], Path(sys.argv[2])

    here = Path(__file__).resolve().parent
    bundles = json.loads(subprocess.run(
        [sys.executable, here / "bundler.py", episodes_dir],
        capture_output=True, text=True, check=True).stdout)["bundles"]

    consumed: set[str] = set()
    for note in (vault / "notes").glob("*.md"):
        if note.name == "README.md":
            continue
        text = note.read_text()
        fm_end = text.index("\n---", 3)
        if re.search(r"^status:\s*active", text[:fm_end], re.M):
            m = re.search(r"^children:\s*\[([^\]]*)\]", text[:fm_end], re.M)
            if m:
                consumed |= {c.strip() for c in m.group(1).split(",")}

    surprise = {}
    for p in Path(episodes_dir).glob("*.md"):
        if p.name == "README.md":
            continue
        text = p.read_text()
        eid = re.search(r"^id:\s*(\S+)", text, re.M)
        s = re.search(r"^surprise:\s*(\d+)", text, re.M)
        if eid and s:
            surprise[eid.group(1)] = int(s.group(1))

    queue = []
    for b in bundles:
        pending = [m for m in b["members"] if m not in consumed]
        queue.append({
            "bundle": b["bundle"],
            "pending": pending,
            "eligible": len(pending) >= 3,
            "priority": sum(surprise.get(m, 0) for m in pending),
        })
    queue.sort(key=lambda q: -q["priority"])
    print(json.dumps({"consumed": sorted(consumed), "queue": queue}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
