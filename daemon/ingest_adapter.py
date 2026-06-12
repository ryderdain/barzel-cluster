#!/usr/bin/env python3
"""ingest_adapter — CONSOLIDATION_DAEMON §7.1.

Normalizes the episodic sources into episode records (spec §2a):
  - RETROSPECTIVE.md            -> one episode per `## <ts> — <title>` entry
  - notes/PROD_RUN_REPORT.md    -> one episode per numbered hiccup-ledger row

Episode records are Markdown files with YAML frontmatter (the shape of
aroni/templates/episode-record.md), written to the vault's episodes/ dir.
Stdlib only (no PyYAML on the host); values are emitted as quoted scalars.

Determinism contract: the episode id is a stable hash of (source, key text),
so re-runs rewrite identical files in place — the adapter is idempotent and
its output is diffable. It WRITES only inside --out; reading is its only
other side effect.

Surprise tagging (spec §2a: hiccups are >0 by construction):
  retrospective -> 0 (verified completions; no expectation was violated)
  hiccup        -> 2 baseline; 3 when the symptom/root-cause text shows the
                   failure was MASKED (matched: 'silently', 'masked',
                   'reported success', 'no motion', 'indefinitely') — a
                   masked failure violates expectation twice: the thing broke
                   AND the signal lied about it.
"""

import argparse
import hashlib
import re
import sys
from pathlib import Path

MASKED_MARKERS = ("silently", "masked", "reported success", "no motion", "indefinitely")


def stable_id(source: str, key_text: str) -> str:
    return hashlib.sha256(f"{source}\n{key_text}".encode()).hexdigest()[:12]


def yaml_quote(s: str) -> str:
    s = " ".join(s.split())  # collapse whitespace/newlines
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def emit_episode(out_dir: Path, *, eid: str, ts: str, source: str, claim: str,
                 expected: str, actual: str, surprise: int, refs: list[str],
                 body: str) -> Path:
    lines = [
        "---",
        f"id: {eid}",
        f"ts: {yaml_quote(ts)}",
        f"source: {source}",
        f"claim: {yaml_quote(claim)}",
        f"expected: {yaml_quote(expected)}",
        f"actual: {yaml_quote(actual)}",
        f"surprise: {surprise}",
        "refs:",
        *[f"  - {yaml_quote(r)}" for r in refs],
        "---",
        "",
        body.strip(),
        "",
    ]
    path = out_dir / f"{eid}.md"
    path.write_text("\n".join(lines))
    return path


def split_row(line: str) -> list[str]:
    # Split on UNESCAPED pipes only (ledger cells contain literal `\|\| true`).
    cells = re.split(r"(?<!\\)\|", line.strip())
    return [c.strip().replace("\\|", "|") for c in cells[1:-1]]


def ingest_hiccups(ledger: Path, out_dir: Path) -> list[dict]:
    episodes = []
    for line in ledger.read_text().splitlines():
        if not re.match(r"^\|\s*\d+\s*\|", line):
            continue
        cells = split_row(line)
        if len(cells) < 6:
            print(f"warning: short hiccup row skipped: {line[:60]}…", file=sys.stderr)
            continue
        num, phase, symptom, root_cause, fix, doc_dest = cells[:6]
        haystack = f"{symptom} {root_cause}".lower()
        surprise = 3 if any(m in haystack for m in MASKED_MARKERS) else 2
        eid = stable_id("hiccup", f"{num}|{symptom}")
        # Mapping (user decision 2026-06-12): claim = the ROOT-CAUSE
        # generalization (the truth the episode established); the fix stays in
        # the body. expected is left empty — the violated assumption is the
        # claim's inverse, and inverting it faithfully is judgment, not
        # adapter mechanics (surprise>0 holds by construction, spec §2a).
        episodes.append(dict(
            eid=eid, ts="2026-06-10", source="hiccup",
            claim=f"[hiccup {num}, {phase}] {root_cause}",
            expected="",
            actual=symptom,
            surprise=surprise,
            refs=[f"barzel-cluster/notes/PROD_RUN_REPORT.md ledger row {num}", doc_dest],
            body=(f"## Hiccup {num} — {phase}\n\n**Symptom.** {symptom}\n\n"
                  f"**Root cause.** {root_cause}\n\n**Fix.** {fix}\n\n"
                  f"**Doc destination.** {doc_dest}"),
        ))
    for e in episodes:
        emit_episode(out_dir, **e)
    return episodes


def ingest_retrospective(retro: Path, out_dir: Path) -> list[dict]:
    episodes = []
    text = retro.read_text()
    # Entries: `## <ts> — <title>` headed sections, body until the next `## `.
    for m in re.finditer(r"^## (\S+) — (.+?)$\n(.*?)(?=^## |\Z)",
                         text, flags=re.M | re.S):
        ts, title, body = m.group(1), m.group(2).strip(), m.group(3).strip()
        eid = stable_id("retrospective", f"{ts}|{title}")
        episodes.append(dict(
            eid=eid, ts=ts, source="retrospective",
            claim=title,
            expected="",
            actual=title,
            surprise=0,
            refs=[f"barzel-cluster/RETROSPECTIVE.md entry {ts}"],
            body=f"## {ts} — {title}\n\n{body}",
        ))
    for e in episodes:
        emit_episode(out_dir, **e)
    return episodes


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    repo_root = Path(__file__).resolve().parent.parent
    ap.add_argument("--retro", type=Path, default=repo_root / "RETROSPECTIVE.md")
    ap.add_argument("--ledger", type=Path, default=repo_root / "notes/PROD_RUN_REPORT.md")
    ap.add_argument("--out", type=Path, required=True,
                    help="episodes output dir (e.g. ../aroni/episodes)")
    args = ap.parse_args()

    args.out.mkdir(parents=True, exist_ok=True)
    hiccups = ingest_hiccups(args.ledger, args.out)
    retros = ingest_retrospective(args.retro, args.out)

    # Report (stdout): counts + the surprise histogram the spec asks us to verify.
    hist: dict[int, int] = {}
    for e in hiccups + retros:
        hist[e["surprise"]] = hist.get(e["surprise"], 0) + 1
    print(f"episodes written : {len(hiccups) + len(retros)} -> {args.out}")
    print(f"  hiccups        : {len(hiccups)}")
    print(f"  retrospective  : {len(retros)}")
    print(f"surprise histogram: {dict(sorted(hist.items()))}")
    zero_surprise_hiccups = [e["eid"] for e in hiccups if e["surprise"] == 0]
    if zero_surprise_hiccups:
        print(f"ERROR: hiccups with surprise=0 (spec §2a violated): {zero_surprise_hiccups}",
              file=sys.stderr)
        return 1
    print("surprise check   : OK (every hiccup > 0)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
