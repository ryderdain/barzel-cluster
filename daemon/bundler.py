#!/usr/bin/env python3
"""bundler — CONSOLIDATION_DAEMON §7.2.

Clusters episode records into candidate bundles via an explicit, reviewable
entity-rule table (regex → entity tag; an episode may carry several tags; a
bundle is every episode sharing a tag). Deterministic by design: at corpus
size ~14, transparent rules beat embeddings — the rules ARE the clustering
hypothesis, and they sit in this file under review like any other code.

Eligibility (spec §3 guard): a bundle needs >= 3 children to be gate-eligible.
Priority (spec §6): bundles are ranked by summed surprise of their members.

Output: a JSON report to stdout (bundle -> members, eligibility, priority).
Read-only; drafting candidate notes from bundles is the model's job, not this
script's.
"""

import json
import re
import sys
from pathlib import Path

# entity -> patterns matched (case-insensitive) against claim + body.
# Reviewed prose for each rule lives in the candidate notes, not here.
ENTITY_RULES = {
    "env_coupling": [
        r"dev-hardcod", r"hardcoded the dev", r"dev default", r"dev refs",
        r"prod copy", r"predates the prod env", r"env-scoped", r"scope cut",
        r"second environment", r"per-env",
    ],
    "masked_failure": [
        r"silently", r"masked", r"reported success", r"no motion",
        r"indefinitely", r"exit(s|ed)? 0",
    ],
    "argo_sync_ops": [
        r"applicationset", r"argocd", r"sync", r"retry budget", r"hook",
        r"crd", r"appset",
    ],
    "doc_drift": [
        r"stale", r"doc(s)? (said|say|drift)", r"contradicted", r"prereq",
        r"never (made|landed|got)", r"runbook", r"tribal knowledge",
    ],
    "state_lifecycle": [
        r"tfstate", r"digest row", r"lock table", r"local state",
        r"state bucket", r"backend\.tf", r"migrate-state",
    ],
}


def parse_episode(path: Path) -> dict:
    text = path.read_text()
    fm = {}
    body_at = 0
    if text.startswith("---"):
        end = text.index("\n---", 3)
        body_at = end + 4
        for line in text[3:end].splitlines():
            m = re.match(r"^(\w+):\s*(.*)$", line)
            if m:
                fm[m.group(1)] = m.group(2).strip().strip('"')
    return {
        "id": fm.get("id", path.stem),
        "source": fm.get("source", "?"),
        "surprise": int(fm.get("surprise", 0) or 0),
        "claim": fm.get("claim", ""),
        "text": text[body_at:],
    }


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <episodes-dir>", file=sys.stderr)
        return 2
    episodes = [parse_episode(p) for p in sorted(Path(sys.argv[1]).glob("*.md"))
                if p.name != "README.md"]

    bundles: dict[str, list[dict]] = {e: [] for e in ENTITY_RULES}
    for ep in episodes:
        haystack = f"{ep['claim']}\n{ep['text']}".lower()
        for entity, patterns in ENTITY_RULES.items():
            if any(re.search(p, haystack) for p in patterns):
                bundles[entity].append(ep)

    report = []
    for entity, members in bundles.items():
        report.append({
            "bundle": entity,
            "members": [m["id"] for m in members],
            "n": len(members),
            "eligible": len(members) >= 3,
            "priority": sum(m["surprise"] for m in members),
            "claims": {m["id"]: m["claim"][:110] for m in members},
        })
    report.sort(key=lambda b: -b["priority"])
    tagged = {m for b in report for m in b["members"]}
    print(json.dumps({
        "episodes": len(episodes),
        "untagged": [e["id"] for e in episodes if e["id"] not in tagged],
        "bundles": report,
    }, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
