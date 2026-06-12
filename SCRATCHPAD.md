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

*(2026-06-12)* **Consolidation daemon — build order §7** (spec:
[CONSOLIDATION_DAEMON.md](CONSOLIDATION_DAEMON.md)). **Step 0 DONE:** vault
scaffolded at the standalone repo `~/Local/github.com/ryderdain/aroni` (spec
§7.0 said in-repo `vault/`; variance recorded in the vault README), both repos
committed + pushed (aroni `c00bc45`, barzel `9807925`), and the
scratch-worktree + atomic-commit write-back **confirmed live** as
`consolidation/pass-000` → ff-only land (`04c277e`). Next: **§7.1 ingest
adapter** (RETROSPECTIVE + notes/PROD_RUN_REPORT → episode records, verify
`surprise` tagging); first milestone is §8 (the 13 hiccups end-to-end through
the gate, one logged arbiter verdict).

## Open considerations

- First bring-up under the `brzl-*` names is unexercised: watch for any
  stragglers the rename sweep couldn't reach (live-account values were all
  retired, but conventions baked into helper scripts deserve a first-run eye).

## Session notes

*(empty)*
