---
id: cand-001
title: "A success signal that does not assert the outcome is not evidence of success"
children: [4101dac63d4f, 49b882286457, 5ee92a46298e]   # hiccups 5, 9, 12
lift: 0.33
confidence: 0.6
status: admitted   # → aroni/notes/cand-001-masked-failure.md (pass-003, 2026-06-12)
admitted_ts: 2026-06-12
---

# The claim

In composite operations — piped streams, multi-step phases, async waits,
fallback-tolerant defaults — the visible success signal (exit code, green
apply, "Running" status) reports only the **last or weakest link**, not the
outcome. Wherever tooling does not explicitly assert its **postcondition**,
a failure can and eventually will ride a success-shaped signal. The fix is
always the same shape: after the operation, verify the *state of the world*
(the object exists, the port answers, the resource is present), never the
operation's own report of itself.

# Conditions under which it predicts

Operations that are composite or tolerant: `a | b` pipelines whose tail can
mask upstream failure (`|| true`), init/apply flows with silent fallback
defaults (local state when no backend block), async operations whose status
is a wait on something deletable (a sync awaiting a hook Job).

# Counterexample boundary (where it stops predicting)

Atomic, single-command failures fail loudly (a refused connection, an auth
rejection, a validation error) — this note does not predict masking there,
and asserting postconditions on such commands adds nothing. It also does not
claim all composite operations fail — only that *when* they fail, the failure
can be invisible unless the postcondition is asserted.
