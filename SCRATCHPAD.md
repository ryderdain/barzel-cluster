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

*(2026-06-12, later)* **cand-002 ADMITTED** (pass-004, narrowed form, arbiter
rationale logged — first real one). Vault: 2 active notes, 7 of 13 hiccups
consumed. **Next drafting cycle: doc_drift** (4 pending, priority 8 — h1
digest rows, h3 ssh flags, h4 token shapes, h8 prereqs; likely claim shape:
"docs drift toward the env that exercised them last; instructions unexercised
since their last change are stale until proven otherwise"). argo_sync_ops
fell ineligible (2 pending) — may merge into a future ops-pattern bundle.

*(superseded below — kept this session for context)*
- `vault_check.py` (§7.5): frontmatter/links/supersession/decision checks —
  clean over the live vault; run it in every pass worktree pre-land.
- `scheduler.py` (§7.6): consumption derived from active notes' children (no
  state file). Current queue: doc_drift 10 > argo_sync_ops 8 = env_coupling 8;
  masked_failure consumed → 0. **doc_drift leads the next drafting cycle.**
- Bundler noise fixed: failure-pattern rules apply to `source=hiccup` only.
- **cand-002**: lift +0.25 (baseline 0.44 — h2/h6/h7 near-clones inflate it;
  the gate's value concentrated in h10 + the discovery-mode claim). Critic
  LANDED a hit via child h2 (pre-empted = review-time find, contradicting
  "runtime, serially") → claim narrowed to audited→review / unaudited→runtime.
  Narrowed form awaits the arbiter. On accept: pass-004 = note + decision
  record, vault_check in the worktree, ff-only land.
- Rationale discipline note stands (pass-003 logged "(none given)").

## Open considerations

- First bring-up under the `brzl-*` names is unexercised: watch for any
  stragglers the rename sweep couldn't reach (live-account values were all
  retired, but conventions baked into helper scripts deserve a first-run eye).

## Session notes

*(empty)*
