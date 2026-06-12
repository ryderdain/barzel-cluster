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
[CONSOLIDATION_DAEMON.md](CONSOLIDATION_DAEMON.md)). **§7.0 DONE** (vault =
standalone `aroni` repo; write-back mechanics proven as pass-000 `04c277e`).
**§7.1 DONE:** `daemon/ingest_adapter.py` (stdlib-only python — no PyYAML on
host) normalizes RETROSPECTIVE + the hiccup ledger → `aroni/episodes/`;
landed as pass-001 (`1ead0ce`): 14 records (13 hiccups, 1 retrospective),
surprise histogram {0:1, 2:10, 3:3} — masked failures auto-escalate to 3;
idempotency proven (re-run over landed output = zero diff). Decision recorded:
episodes live IN the vault so `children:` links resolve as Obsidian links.
Next: **§7.2 bundler** (cluster episodes → candidate bundles, draft one
candidate note per bundle), then **§7.3 the SINBAD gate** against the 13
hiccups as fixtures. Milestone §8 = one gated candidate + one logged verdict.

## Open considerations

- First bring-up under the `brzl-*` names is unexercised: watch for any
  stragglers the rename sweep couldn't reach (live-account values were all
  retired, but conventions baked into helper scripts deserve a first-run eye).

## Session notes

*(empty)*
