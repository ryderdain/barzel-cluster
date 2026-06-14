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

*(2026-06-14, opus — SESSION HANDOFF.)* aroni's machinery is complete through
the second order; the user is opening two new sessions: **(a) an aroni session**
to keep open and tweak; **(b) a barzel session for a major refactor**, which aroni
should help drive.

**aroni state (full picture in RETROSPECTIVE 2026-06-14 entries):**
- **4 admitted notes** (cand-001 masked-failure /4 children, cand-002 env-coupling,
  cand-003 doc-rot, cand-004 SSOT). **17 episodes, 5 decision passes** (vault at
  aroni `b5744e3`). Self-contained + portable + shared (hooks, `init_project`).
- **Doctrine (METHOD):** subordinating generalizations; **failure-driven** narrowing;
  the **seam test** (one-question seam/source classifier); the **intersection test**
  (2nd-order gate = seam-boundary AND ≥1 *demonstrated* co-firing; lift demoted to a
  sanity check); **co-fire re-evaluation** (shared new child → re-gate subordinates,
  wire/narrow/merge — verified Hebbian). 
- **The loop is CLOSED + enforced:** `vault_check` fails any pass that lands a
  co-firing unless both notes acknowledge it in `cofires:`; `intersections.py
  --work-order` emits the re-gate tasks. Code detects+enforces; the model judges.
- **cand-005 "context-seam"** (first 2nd-order note) is **HELD** — passes the seam
  boundary but has **zero demonstrated intersections** yet (the instrument caught my
  over-reach). It admits when a real co-firing appears.
- **Next aroni move:** ingest the 3 new surprise-0 RETROSPECTIVE episodes (barzel
  RETRO grew); run a normal cycle. Watch for the **first co-firing** — that's the
  event that could finally admit cand-005 and exercise the closed loop for real.

**barzel refactor (next session):** a major refactor is coming — see BACKLOG items
1–4 (automation overhaul vs GUIDANCE; env DRY/consolidation; multi-account CI). aroni
should assist: as you hit decisions/failures, they become episodes (log them in
RETROSPECTIVE / a build ledger) → consolidation. Expect the refactor to *generate*
the corpus that grows aroni — the flywheel.

## Open considerations

- First bring-up under the `brzl-*` names is unexercised: watch for any
  stragglers the rename sweep couldn't reach (live-account values were all
  retired, but conventions baked into helper scripts deserve a first-run eye).

## Session notes

*(detail lives in `aroni/decisions/pass-008..012` + `_candidates/`; not restated
here — Current focus is the live snapshot.)*
