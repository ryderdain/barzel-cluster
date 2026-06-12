---
id: cand-002
title: "Duplicating an environment surfaces every implicit single-env assumption — at review when audited, serially at runtime when not"
children: [68c4dba5c308, b0aee68843af, 113a4be679f1, c0cabbd02ff3]   # hiccups 2, 6, 7, 10
lift: 0.25
confidence: 0.6
status: admitted   # → aroni/notes/cand-002-env-coupling.md (pass-004, 2026-06-12)
admitted_ts: 2026-06-12
---

# The claim (narrowed once by the gate's critic — see gate_runs/cand-002.md)

Code written while only one environment exists accumulates implicit
single-environment assumptions (hardcoded names, paths, key files, scope
cuts) that are invisible until a second environment exercises the same path.
They surface at first use — **at runtime when unaudited; a targeted
env-value audit at duplication time converts them to review-time finds**.
Unaudited duplication therefore produces a *serial* sequence of runtime
discoveries, one per assumption, at each value's point of first use.

# Conditions under which it predicts

Dev→prod style duplication of imperative tooling and config. The discovery
mode is the falsifiable edge: audited values are found at review (child h2,
pre-empted by grep); unaudited ones fail at runtime, serially (h6, h7, h10).

# Counterexample boundary (where it stops predicting)

Not values parameterized from birth (nothing implicit to surface). Not
conscious, *recorded* design divergences (those resurface as review
questions, not failures — h10 qualified only because its cut was unrecorded
and unasked). Not copying omissions (h5 — an error in making the copy, not
an assumption inherited through it).
