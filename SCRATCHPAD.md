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

*(2026-06-14, opus)* **aroni made durable + portable; between consolidation cycles.**
This session's structural work (all landed + pushed):
- **Survival hooks** in barzel `.claude/settings.json` — SessionStart injects the
  scratchpad focus + last vault passes every session (compaction-proof, prose-decay-
  proof); PreCompact nudges a flush. The hook surfaces state to the *human* too —
  cheap re-invocation is what makes aroni survive, not my unprompted diligence.
- **aroni is now self-contained + shared**: `daemon/` moved out of barzel into the
  aroni repo (`tools/`, `SPEC.md`, `METHOD.md`). barzel is just an episode source.
  One shared vault across all projects (universal beliefs transfer); notes carry a
  `scope:` field. ingest is source-path explicit (portable; retro-only works for
  non-infra domains).
- **Adoption is one idempotent command**: `aroni/tools/init_project.py <repo>` installs
  the hooks (this is how they *travel*), scaffolds memory files, emits the CLAUDE.md
  anchor. Guide: `aroni/ADOPTING.md`. (A signature bug duplicated PreCompact on first
  run — caught by dogfooding, fixed; hooks are ASCII so machine-written JSON is byte-stable.)

**Consolidation state unchanged this session:** 3 admitted notes (cand-001/002/003)
consume 10/13 hiccups; corpus exhausted at the bundle level (h3/h11/h13 sub-floor).
Between cycles until new episodes arrive. NB: barzel `RETROSPECTIVE.md` has grown to
4 entries — the next ingest will surface 3 new surprise-0 episodes.

**Seeds forward:** (1) fix-propagation bundle (h3 + a sibling — none in corpus yet);
(2) cand-001 + cand-003 refinement (arbiter-flagged supersession candidates);
(3) second-order pass over the notes themselves once more first-order notes exist
(cand-001/002/003 share a root: single-context dev hides assumptions until contact).
**Tabled (BACKLOG):** aroni `lift` is judge-relative — not comparable across passes
by different models without a one-judge re-gate.

## Open considerations

- First bring-up under the `brzl-*` names is unexercised: watch for any
  stragglers the rename sweep couldn't reach (live-account values were all
  retired, but conventions baked into helper scripts deserve a first-run eye).

## Session notes

*(2026-06-14)* **review-001 PENDING arbiter** (`aroni/_candidates/`, pass-008).
The first self-referential cycle: 2 episodes from building aroni
(`8b8a3678bbcf` init idempotency bug; `df037edd9536` relocation doc-dup) — both
map to existing notes. Asks: (1) add ep A to cand-001 as a child + conf 0.6→0.7
(cross-domain); (2) SSOT seed ep B + h11 (`d320583ddb68`) — bank at n=2 or fold
into cand-003. On verdict → pass-009 write-back (amend cand-001 children).
