# Gate run — cand-002 (spec §3, leave-one-out + falsification)

- **Candidate:** cand-002 "Duplicating an environment surfaces every implicit
  single-env assumption…" — children 68c4dba5c308 (h2) · b0aee68843af (h6) ·
  113a4be679f1 (h7) · c0cabbd02ff3 (h10)
- **Judge:** the consolidating model (spec §3 caveat: soft scores, lift
  ordinal). Same rubric as cand-001 (0 / 0.25 / 0.5 / 0.75 / 1).
- **Threshold:** τ = 0.15.

## Leave-one-out

### Hide h2 (bootstrap_argocd.sh — 4 hardcoded dev refs)
- **Baseline** (h6, h7, h10): three dev-coupling failures visible → "another
  script holds dev-hardcoded values that break in prod" is reachable. **0.5**
- **With-N:** adds the *first-use, serial* framing → "the GitOps bootstrap
  script, written before prod existed, carries dev refs that surface at the
  prod gitops phase." **0.75**

### Hide h6 (cluster phase — dev layer path + inventory/dev.yml + kubeconfig)
- **Baseline** (h2, h7, h10): same shape as h2/h7 → **0.5**
- **With-N:** **0.75**

### Hide h7 (ansible.cfg — dev-hardcoded SSH key path)
- **Baseline:** **0.5** · **With-N:** **0.75**

### Hide h10 (monitoring scope-cut → ServiceMonitor CRD absent)
- **Baseline** (h2, h6, h7 — all hardcode-shaped): predicts "another
  hardcoded value"; h10 is a different shape (an unrecorded scope cut whose
  dependency surfaced later). Theme only. **0.25**
- **With-N:** the note names scope cuts explicitly → "a deliberate but
  unrecorded reduction in prod broke something that assumed dev's full
  shape." Mechanism (the CRD) not derivable. **0.5**

## Lift

| child | E_base | E_N |
|-------|--------|-----|
| h2    | 0.50   | 0.75 |
| h6    | 0.50   | 0.75 |
| h7    | 0.50   | 0.75 |
| h10   | 0.25   | 0.50 |

**E_base = 0.4375 · E_N = 0.6875 · lift = +0.25** → clears τ=0.15.
Honest observation: baseline is much higher than cand-001's (0.44 vs 0.25)
because h2/h6/h7 are near-clones that predict each other *without* the note —
the note's marginal value concentrates in h10 and in the serial-at-first-use
framing. Lower lift than cand-001 is the gate working, not failing.

## Falsification (critic seat) — **a hit landed, on a child**

- **Attack:** the claim said assumptions surface "one **runtime** failure at
  a time." Child **h2's own ledger row contradicts this** — it is marked
  *(pre-empted)*: the dev refs were found by **review** (a grep during prep)
  and fixed *before* the run. The note as drafted mispredicted the discovery
  mode of one of its own children.
- **Resolution (claim narrowed, per §3.4):** the claim now reads
  "…surface at first use — **at runtime when unaudited; a targeted env-value
  audit converts them to review-time finds**." The narrowed form predicts h2
  (audited → review-time) AND h6/h7/h10 (unaudited → runtime) — and is more
  useful: it carries the prescription (audit on duplication) as part of the
  prediction.
- **Residual attacks:** h5 (backend.tf omission) probed — a *copying
  omission*, not an inherited assumption; outside the claim, not mispredicted.
  Truism probe — "duplication reveals assumptions" alone would be
  unfalsifiable; the falsifiable content is the discovery-mode prediction
  (runtime-vs-review as a function of auditing), which h2 just exercised.

## Emit → arbiter

Note: the **narrowed** form is what's proposed for admission (candidate file
updated in place; the pre-narrowing form is in git history). Verdict:
**accept / revise / reject + one-line rationale**.
