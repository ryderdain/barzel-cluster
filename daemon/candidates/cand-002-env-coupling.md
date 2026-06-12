---
id: cand-002
title: "Duplicating an environment surfaces every implicit single-env assumption, one runtime failure at a time"
children: [68c4dba5c308, b0aee68843af, 113a4be679f1, c0cabbd02ff3]   # hiccups 2, 6, 7, 10
lift:         # not yet gated — queued behind cand-001
confidence:
status: candidate
admitted_ts:
---

# The claim

Code written while only one environment exists accumulates implicit
single-environment assumptions (hardcoded names, paths, key files, scope
cuts) that are invisible until a second environment runs the same path; each
then fails at runtime, serially, at the point of first use. Predicts that
environment duplication without a systematic audit of env-bearing values
produces a sequence of run-time discoveries rather than one review-time fix.

# Conditions / boundary (draft — to be sharpened by the gate's critic)

Predicts dev→prod style duplication of imperative tooling and config.
Does not predict failures in values that were parameterized from birth, nor
design divergences chosen consciously and recorded (those fail differently —
as review questions, not runtime surprises).
