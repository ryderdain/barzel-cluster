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

*(2026-06-12)* **Consolidation daemon: §8 MILESTONE COMPLETE** — full RETRO
entry has the record. Open threads, in order:
- **cand-002 (env-coupling)** drafted, ungated — next gate run (4 children =
  8 leave-one-out tasks). Sharpen its boundary via the critic.
- **Bundler noise:** keyword rules pulled the retrospective founding record
  into `argo_sync_ops`; consider a `source != retrospective` filter for
  hiccup-pattern bundles, or weight rules by field (claim vs body).
- **§7.5 write-back checks** not yet automated (link integrity / orphan scan
  ran by eye this pass) and **§7.6 scheduler** unbuilt — both fine at n=1
  pass, needed before passes get routine.
- Rationale discipline: pass-003's accept logged with rationale "(none
  given)" — fine once, but the §7.7 shadow-arbiter path starves without
  real rationales; nudge (don't nag) at future verdicts.

## Open considerations

- First bring-up under the `brzl-*` names is unexercised: watch for any
  stragglers the rename sweep couldn't reach (live-account values were all
  retired, but conventions baked into helper scripts deserve a first-run eye).

## Session notes

*(empty)*
