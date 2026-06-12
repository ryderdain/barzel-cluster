# Gate run — cand-001 (spec §3, leave-one-out + falsification)

- **Candidate:** cand-001 "A success signal that does not assert the outcome
  is not evidence of success"
- **Children:** 4101dac63d4f (hiccup 5) · 49b882286457 (hiccup 9) ·
  5ee92a46298e (hiccup 12)
- **Judge:** the consolidating model itself (spec §3 caveat applies: scores
  are soft, **lift is ordinal**). Rubric: fidelity of the predicted salient
  claim to the hidden child's actual claim — 0 none / 0.25 theme only /
  0.5 theme + failure shape / 0.75 + mechanism / 1.0 near-verbatim.
- **Threshold:** τ = 0.15.

## Leave-one-out

### Hide 4101dac63d4f (hiccup 5 — backend.tf missing → silent local state)
- **Baseline** (from 9, 12 only): predicted "some step reported success while
  its real outcome had failed." Theme only — the *mechanism* (init's silent
  local-state fallback when no backend block exists) is not derivable from a
  bash exit-code mask and a ghost-hook wait. **0.25**
- **With-N:** the note directs the prediction to "which postcondition went
  unasserted?" → predicted "an apply succeeded while its durable artifact
  (state in the backend) was never verified present." Captures theme +
  failure shape; mechanism still not specific. **0.5**

### Hide 49b882286457 (hiccup 9 — `|| true` tail masks failed bootstrap)
- **Baseline** (from 5, 12): predicted "a status lied about completion."
  Theme only. **0.25**
- **With-N:** the note names tolerant pipeline tails explicitly → predicted
  "a piped/chained phase exited 0 because its last command was tolerant,
  masking an upstream failure; fix = assert the produced resource exists."
  Theme + shape + mechanism — close to the actual fix (the post-run
  ApplicationSet assert). **0.75**

### Hide 5ee92a46298e (hiccup 12 — sync wedged on hand-deleted hook)
- **Baseline** (from 5, 9): predicted "a green/quiet state concealed a dead
  operation." Theme only; the ghost-wait mechanism isn't inferable. **0.25**
- **With-N:** the note's async-wait condition → predicted "an operation's
  'Running' status was a wait on something that no longer existed — the
  status asserted activity, not the existence of the awaited object."
  Theme + shape + most of the mechanism. **0.5**

## Lift

| child | E_base | E_N |
|-------|--------|-----|
| h5    | 0.25   | 0.50 |
| h9    | 0.25   | 0.75 |
| h12   | 0.25   | 0.50 |

**E_base = 0.25 · E_N = 0.583 · lift = +0.33** → clears τ=0.15 with margin
(ordinal reading: the note materially improves mutual predictability of its
children; it is not redundant with them).

## Falsification (critic seat)

**Strongest attack attempted:** find a corpus episode the note *mispredicts*.
Candidates tried:
- **Hiccup 1** (digest rows broke `tofu init`) — failed loudly at first use.
  The note does not claim all failures are masked, only unasserted composite
  successes; a loud atomic failure is outside its stated boundary. **Attack
  does not land.**
- **Hiccup 3** (ssh `MaxAuthTries`) — loud auth rejection; same boundary.
  **Does not land.**
- **Over-breadth probe:** does the note demand postcondition asserts on
  atomic commands where they add nothing? As originally drafted it could be
  read that way — the **boundary section was narrowed during this run** to
  composite/tolerant/async operations explicitly. With that boundary, no
  corpus episode is mispredicted.

**Critic conclusion:** no landed counterexample at n=14; the note survived
one boundary narrowing. Weakness to record: all three children come from a
single two-day operational burst by the same toolchain author — the note has
never been tested against an unrelated codebase's failures.

## Emit → arbiter

Verdict requested: **accept / revise / reject + one-line rationale**
(decision record → `aroni/decisions/pass-003.md`; on accept, write-back of
the note + provenance is the same pass).
