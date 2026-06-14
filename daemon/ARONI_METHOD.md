# ARONI_METHOD — the consolidation skill (repeated procedure)

The standing loop that turns episodic records into arbitrated semantic beliefs.
Spec + invariants: `CONSOLIDATION_DAEMON.md`. This file is the *how*, run each
cycle. Invoked by the keyword **aroni** (CLAUDE.md).

## The cycle

0. **Invariants** (CONSOLIDATION_DAEMON §1): the vault is mutated only via pass
   commits in a scratch worktree; `RETROSPECTIVE.md` is read-only; the decision
   log is append-only; a landed pass is one atomic ff-only commit or none.
1. **SCHEDULE** — `scheduler.py <episodes> <vault>` → the highest-priority
   eligible bundle (≥3 unconsumed children; consumption derived from active
   notes, not a state file).
2. **DRAFT** — write candidate note(s) for the bundle: title + claim (a
   root-cause generalization), the conditions under which it predicts, the
   counterexample boundary, `children`, a provenance stub.
3. **GATE** — leave-one-out lift + a falsification critic (CONSOLIDATION_DAEMON
   §3). Narrow or eject children the critic mispredicts; an ejected child is
   *seeded forward* (named as a future bundle), not discarded. The gate run is
   authored beside the candidate and surfaced with it.
4. **SURFACE** — stage candidate (`cand-NNN.md`) + gate run (`cand-NNN.gate.md`)
   into `aroni/_candidates/` via a pass, so the arbiter reads them in Obsidian.
   Summarize compactly in chat **and** point at the in-vault files. (This step
   exists because candidates were once buried in chat — refinement 2026-06-14.)
5. **ARBITER** — request accept / revise / reject. Rationale **required** for
   reject/revise and non-obvious accepts; **optional** for a face-valid accept.
6. **WRITE-BACK** — a pass: accept → note to `notes/`, gate run to `gate_runs/`;
   reject → both to `_rejected/`; a decision record either way
   (`decisions/pass-NNN.md`); run `vault_check.py` in the worktree **before**
   the ff-only land.

## Candidate lifecycle (where things live)

- `aroni/_candidates/cand-NNN.md` + `.gate.md` — pending arbiter review.
- accept → `aroni/notes/` (active) + `aroni/gate_runs/` (gate provenance).
- reject → `aroni/_rejected/` (note + gate; never discarded — the negative set).

cand-001/002 predate this surfacing convention: their drafts live in
`daemon/candidates/` and gate runs in `daemon/gate_runs/`, referenced as
historical. Everything from cand-003 onward lives in the vault.

## On rationale (refinement 2026-06-14)

The decision log trains the future shadow-arbiter (CONSOLIDATION_DAEMON §7.7),
which learns from the rationales that *exist* — rejects, revises, non-obvious
accepts. A face-valid accept is its own learnable class (gate-cleared +
accepted, no words needed); demanding a rationale there manufactures noise.
Belief-refinement is deferred to a later pass **by design** — a correct-on-its-
face note admitted today and sharpened next month is the aroni method working,
not a debt. (cand-001 was flagged by the arbiter as likely-refinable; that is a
forward note, not a defect in the admission.)
