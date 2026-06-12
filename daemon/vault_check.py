#!/usr/bin/env python3
"""vault_check — CONSOLIDATION_DAEMON §7.5 (write-back checks).

Asserts the vault's desired state (spec §5) instead of trusting the pass that
produced it — the daemon eating the platform's own dog food (vault note
cand-001: verify postconditions, never the operation's report of itself):

  1. frontmatter completeness — every active note carries id / children /
     lift / status / admitted_ts;
  2. link integrity — every `children:` id resolves to an episode or note;
  3. supersession — every `superseded:<id>` names an existing note, and no
     pair of notes is simultaneously active under the same id;
  4. decisions — every admitted note's admitting pass has a decision file.

Read-only; exits nonzero on any violation. Run against a pass worktree
BEFORE the ff-only land, and against the landed vault any time.
"""

import re
import sys
from pathlib import Path


def frontmatter(path: Path) -> dict:
    text = path.read_text()
    fm = {}
    if text.startswith("---"):
        for line in text[3:text.index("\n---", 3)].splitlines():
            m = re.match(r"^(\w+):\s*(.*)$", line)
            if m:
                fm[m.group(1)] = m.group(2).split("#")[0].strip().strip('"')
    return fm


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <vault-root>", file=sys.stderr)
        return 2
    vault = Path(sys.argv[1])
    errors: list[str] = []

    episode_ids = {frontmatter(p).get("id", p.stem)
                   for p in (vault / "episodes").glob("*.md") if p.name != "README.md"}
    notes = {p: frontmatter(p)
             for p in (vault / "notes").glob("*.md") if p.name != "README.md"}
    note_ids = {fm.get("id", p.stem) for p, fm in notes.items()}
    known = episode_ids | note_ids

    seen_active: dict[str, Path] = {}
    for path, fm in notes.items():
        rel = path.relative_to(vault)
        for field in ("id", "children", "lift", "status", "admitted_ts"):
            if not fm.get(field):
                errors.append(f"{rel}: missing/empty frontmatter field `{field}`")
        for cid in re.findall(r"[0-9a-f]{12}|cand-\d+", fm.get("children", "")):
            if cid not in known:
                errors.append(f"{rel}: child `{cid}` resolves to nothing in the vault")
        status = fm.get("status", "")
        if status.startswith("superseded:"):
            target = status.split(":", 1)[1].strip()
            if target not in note_ids:
                errors.append(f"{rel}: superseded-by `{target}` does not exist")
        elif status == "active":
            nid = fm.get("id", path.stem)
            if nid in seen_active:
                errors.append(f"{rel}: id `{nid}` active twice (also {seen_active[nid].name})")
            seen_active[nid] = path

    decision_passes = {p.stem for p in (vault / "decisions").glob("pass-*.md")}
    for path, fm in notes.items():
        body = path.read_text()
        m = re.search(r"\[\[\.\./decisions/(pass-\d+)\]\]|Admitted (pass-\d+)", body)
        admitting = next((g for g in (m.groups() if m else ()) if g), None)
        if admitting and admitting not in decision_passes:
            errors.append(f"{path.relative_to(vault)}: admitting {admitting} has no decision file")

    if errors:
        print("\n".join(f"FAIL {e}" for e in errors))
        return 1
    print(f"vault OK: {len(notes)} note(s), {len(episode_ids)} episode(s), "
          f"{len(decision_passes)} decision file(s); links, supersession, "
          f"frontmatter, decisions all clean")
    return 0


if __name__ == "__main__":
    sys.exit(main())
