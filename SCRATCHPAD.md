# SCRATCHPAD — working memory (volatile, user-exposed)

The agent's short-term store: session comments, considerations, partial
conclusions, and state worth surviving a context compaction — kept here so the
user can see (and correct) the working memory at any time. Works **in tandem**
with the agent's internal cycles, not instead of them.

**Contract:**
- Freely written and rewritten during a session; stale content is pruned, not
  preserved. Nothing here is a record — durable outcomes graduate to
  [RETROSPECTIVE.md](RETROSPECTIVE.md) once user-verified; planned work moves
  to [BACKLOG.md](BACKLOG.md).
- Update it at natural checkpoints: when picking up a task, on a significant
  finding or direction change, and before ending a session.
- The user may edit or annotate at will; treat their text as instruction.

---

## Current focus

*(2026-06-14, opus)* **aroni method formalized + doc_drift cycle surfaced,
verdict PENDING.** Refinements taken on board this session (user-directed):
- **Keyword "aroni"** = the vault + the consolidation method/skill — anchored
  in CLAUDE.md; the repeated procedure is `daemon/ARONI_METHOD.md`.
- **Candidates surfaced in-vault**: new `aroni/_candidates/` tray (note +
  `.gate.md`) so the arbiter reads them in Obsidian, not buried in chat;
  `aroni/gate_runs/` is the post-admission gate-provenance home. (cand-001/002
  artifacts stay in `barzel-cluster/daemon/`, historical.)
- **Rationale optional on face-valid accepts** (required for reject/revise +
  non-obvious accepts). pass-003's "(none given)" is now legitimate, not a
  debt; deferring belief-refinement to a later pass IS the method.

**doc_drift cycle — cand-003** staged for review in `aroni/_candidates/`
(pass-005, `4079eb3`): "docs/procedures are stale-until-exercised." Gate
landed a hit → **h3 ejected** (missing `IdentitiesOnly` is config
fix-propagation, not doc staleness); narrowed to h1/h4/h8, lift +0.30.
Awaiting arbiter verdict → then pass-006 write-back.

**Seeds forward:** (1) h3 + a sibling → a future "fix doesn't propagate across
parallel surfaces" bundle. (2) cand-001 flagged by the arbiter as
likely-refinable by a later pass — a supersession candidate, not a defect.

## Open considerations

- First bring-up under the `brzl-*` names is unexercised: watch for any
  stragglers the rename sweep couldn't reach (live-account values were all
  retired, but conventions baked into helper scripts deserve a first-run eye).

## Session notes

*(empty)*
