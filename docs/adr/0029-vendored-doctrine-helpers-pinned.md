# ADR-0029 — The Bash doctrine helpers are vendored, pinned to a tagged commit

**Status:** Accepted · **Date:** 2026-10-14

**Context.** The driver sources two helpers from `ryderdain/bash`:
`includes/runlib.sh` and `includes/error.sh`. Decision Q49 (2026-10-09) kept
copies in `driver/lib/` only while the doctrine branch was unmerged, and
planned to source the sibling checkout directly after the merge. A direct
source works only where `../bash` is checked out. The kiesei image and the
conductor run in containers and need their own copy. A moving branch also
makes runs not reproducible.

**Decision.**

- **Keep the copies in `driver/lib/`, byte-identical to one commit** on
  `ryderdain/bash` master. `driver/lib/UPSTREAM` names the repo, the branch,
  a tag (`barzel-cluster/2026-10-14`) and the commit.
- **`driver/lib/upstream-check.sh` compares each copy with the tag.** It
  fails if a copy differs from the pin. It reports, but does not fail, when
  the branch has a newer version: moving the pin is a choice.
- **To move the pin:** review the change, copy the files, tag the new commit,
  update `UPSTREAM`, and commit in both repos.

**Consequences.**

- Every locus runs the same helpers, and each run can be reproduced.
- A doctrine change reaches this repo only by a deliberate pin move.
- *Alternatives considered.* Source the sibling checkout (Q49): only on the
  operator's machine, and each kiesei build gets whatever is checked out.
  A git submodule: one more mechanism for two files.
