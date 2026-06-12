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
[CONSOLIDATION_DAEMON.md](CONSOLIDATION_DAEMON.md)). Step 0 scaffold staged:
the vault is the standalone repo `~/Local/github.com/ryderdain/aroni`
(NOT in-repo `vault/` as the spec's §7.0 wording assumed — README there records
the variance). Remaining in step 0: the scratch-worktree + atomic-commit
write-back confirmation, blocked on aroni's initial commit (worktrees need a
HEAD). Next: §7.1 ingest adapter; first milestone is §8 (the 13 hiccups
end-to-end through the gate).

## Open considerations

- First bring-up under the `brzl-*` names is unexercised: watch for any
  stragglers the rename sweep couldn't reach (live-account values were all
  retired, but conventions baked into helper scripts deserve a first-run eye).

## Session notes

*(empty)*
