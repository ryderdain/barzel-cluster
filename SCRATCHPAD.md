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

*(2026-06-14, opus)* **aroni self-referential arc — cand-005 pending (iii).**
(Durability+portability done earlier this session: hooks, self-contained shared
vault, `init_project`; recorded in RETROSPECTIVE.)

**The live thread — the vault consolidating its own construction:**
- **4 admitted notes.** cand-001 (masked-failure, now 4 children incl. the build-bug
  `8b8a3678bbcf`, conf 0.7), cand-002 (env-coupling), cand-003 (doc-rot, left whole),
  cand-004 (SSOT, admitted pass-011).
- **Doctrine in METHOD:** subordinating generalizations + **failure-driven** narrowing
  + the **seam test** (`d19417a`: "does the fix read both contexts and check they
  agree?" yes=seam/no=source). The seam test is the wire/snip mechanism (Hebbian).
- **cand-005 "context-seam"** — first **second-order** note (children are notes:
  cand-001/002/003/004). "A property true in one context breaks on contact with a
  second; the bug lives in the *relation*, invisible from either side → instrument
  the seam, don't fortify the source." (i) falsifiable via the seam test ✓; (ii)
  cand-001 seated ✓; **(iii) OPEN: the second-order instrument.** Explained `lift`
  in depth. Agent rec: **demote lift to a sanity check at second order**; let the
  *intersection test* (parent predicts co-firings no child predicts alone —
  h11=002∩004) + *seam boundary* carry releveling. cand-005 stays candidate until
  (iii) is set → then re-emit for the admission verdict.

**Seeds forward:** (1) fix-propagation bundle (h3 + a sibling — none in corpus yet);
(2) on (iii) resolving, the second-order *instrument* likely needs encoding in
SPEC/METHOD (intersection test + seam boundary as the releveling gate); (3) next
ingest surfaces 3 new surprise-0 RETROSPECTIVE episodes (barzel RETRO has grown).
**Tabled (BACKLOG):** aroni `lift` is judge-relative — not comparable across passes
by different models without a one-judge re-gate (this feeds the (iii) decision).

## Open considerations

- First bring-up under the `brzl-*` names is unexercised: watch for any
  stragglers the rename sweep couldn't reach (live-account values were all
  retired, but conventions baked into helper scripts deserve a first-run eye).

## Session notes

*(detail lives in `aroni/decisions/pass-008..012` + `_candidates/`; not restated
here — Current focus is the live snapshot.)*
