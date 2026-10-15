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

*(2026-10-15, fable. Pruned to the current state; the history is in git,
the plan in [BACKLOG.md](BACKLOG.md), the records in
[RETROSPECTIVE.md](RETROSPECTIVE.md).)*

**Pass 5c DONE and user-verified** (RETROSPECTIVE 2026-10-15; branch
`pass-5c-portal` merged to `main`). The cluster follows `main` after the
next phase-30 run, or at once if `brzl.dev/revision` is updated; today it
follows `pass-5c-portal`, which equals `main`.

**▶ NEXT: pass 5d, the example app** (chofesh; ADR-0034; BACKLOG item 3,
"keep it short"). Before it, BACKLOG item 14 when the user wants: the
`*.localhost` default test on sleipnir (clear the CA trust and the resolver
file, set `BRZL_PORTAL_HOST=brzl-local.localhost`, `up`). Open: the Argo CD
upgrade (item 13), `spike-logs` may be deleted once the cluster follows
`main`.
