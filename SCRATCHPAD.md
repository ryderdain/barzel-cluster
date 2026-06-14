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

## Refactor item 1 — pass 1 LANDED (pending live verify), 2026-06-14 (opus)

The "fix carried bugs first" entry to the automation overhaul. Four changes, all
offline-validated (bash -n + shellcheck clean; `_run_phases` resume hint tested in
BOTH direct-run and sourced modes incl. the `if ! cmd; rc=$?` negation-capture bug,
now fixed):

1. **`operator()` no longer lies.** New `gitops/bootstrap/install_ebs_csi.sh`
   (emit-style, sourceable) renders the SAME committed `ebs-csi/values.yaml` the
   ApplicationSet wave 0 uses → the standalone DR path can't drift from GitOps.
   `operator()` previews→confirms→pipes it, then asserts the `gp3` class exists.
2. **`preflight()` backend guard** — warns if any layer lacks `backend "s3"`
   (missing = silent LOCAL state).
3. **`_run_phases`** — on any phase failure prints the stopped phase + exact resume
   command + phases not reached. Dual-mode (EXIT trap direct / return-catch sourced).
4. **`generate-inventory.sh` → `generate_inventory.sh`** (snake_case); live callers
   updated, `notes/` history untouched.

**Not yet RETROSPECTIVE** — needs a live `platform.sh restore` (or at least
`operator`) run to user-verify before it graduates (RETROSPECTIVE = verified+immutable).

### aroni hook for the parallel session — a real CO-FIRING to ingest
The `operator()` bug is a genuine co-firing of **cand-001 (masked-failure)** ×
**cand-003 (doc-rot)**: an honest-looking comment + a hedge `end_function` message
*claimed* a storage install the body never did, masking a DR failure (PVCs hang
Pending) that only fires in the recover path. This is the kind of demonstrated
intersection the intersection-test wants — possibly the event that admits
**cand-005 (context-seam)**. Episode lives here until the work is verified + lands
in RETROSPECTIVE; the aroni session can ingest from there.

## Open considerations

- First bring-up under the `brzl-*` names is unexercised: watch for any
  stragglers the rename sweep couldn't reach (live-account values were all
  retired, but conventions baked into helper scripts deserve a first-run eye).
- **Env-coupling found (item 3):** `ebs-csi/values.yaml` hardcodes `brzl-dev-k8s`;
  prod consumes it too. Recovery path is dev-pinned end-to-end. Park for item 3.

## Session notes

*(detail lives in `aroni/decisions/pass-008..012` + `_candidates/`; not restated
here — Current focus is the live snapshot.)*
