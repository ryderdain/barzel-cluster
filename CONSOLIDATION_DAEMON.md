# CONSOLIDATION_DAEMON — spec & build plan

Handoff brief for the implementing agent. Self-contained: assumes only the
barzel-cluster repo conventions (BACKLOG / SCRATCHPAD / RETROSPECTIVE + the
agent's internal MEMORY index). It adds a **semantic** memory tier (the *vault*)
and a **consolidation daemon** ("the dreamer") that promotes episodic records
into the vault through a SINBAD-style predictive gate, with a human as final
arbiter.

---

## 0. Orientation

- **Memory tiers today:** BACKLOG (intentions) → SCRATCHPAD (working) →
  RETROSPECTIVE (episodic: append-only, immutable, user-verified) + internal
  MEMORY index.
- **New tier — VAULT (semantic):** an Obsidian dir of atomic, linked Markdown
  notes. Mutable, curated. Holds *current best beliefs* — "sources of
  correlation" — not a time log.
- **Daemon = the slow loop.** Reads episodic source, drafts candidate semantic
  notes, validates them by prediction, presents survivors to the human, writes
  accepted notes to the vault. Runs offline/async ("dreaming"), interruptible.
- **Hard split:** the daemon **never** mutates RETROSPECTIVE. Episodic =
  immutable audit trail; semantic = mutable model, always re-derivable from it.
  A botched consolidation is recoverable because the source is untouched.

## 1. Invariants (do not violate)

1. RETROSPECTIVE.md is **read-only** to the daemon. Never edited.
2. The vault is mutated **only** by the daemon, **only** via git: one commit per
   consolidation pass. No partial writes.
3. Interruptible means *abandon cleanly*. Stage every pass in a scratch
   worktree/branch; land it as a single atomic commit or none. An interrupt
   never leaves a torn vault.
4. Every admitted note carries provenance: links to its children **and** its
   predictive-lift score. A note backing no validated prediction is not admitted.
5. The decision log is append-only. Rejections and revisions are data, not
   deletions.
6. The human arbiter is final (for now). The gate filters; it never auto-admits.

## 2. Data contracts (the load-bearing artifacts — build these first)

### 2a. Episode record (ingest-normalized)
Derived from RETROSPECTIVE entries and the hiccup ledger
(`notes/PROD_RUN_REPORT.md`).

```yaml
id:          # stable hash of source
ts:          # source timestamp
source:      # retrospective | hiccup | scratchpad
claim:       # what is asserted true (1–2 lines)
expected:    # what was predicted/assumed (may be empty)
actual:      # what happened
surprise:    # 0–3; >0 iff expected != actual — drives priority
refs:        # links to source docs / ADRs / other episodes
```
`surprise` is the prioritization signal. Hiccups are `surprise > 0` by
construction; they are the richest training signal, so they lead the queue.

### 2b. Vault note (semantic)
Obsidian Markdown. The note *is* a predictive claim.

```yaml
---
id:
title:        # the source-of-correlation, stated as a claim
children:     # ids of episodes/notes this note claims to predict
lift:         # predictive-lift score that admitted it (see §3)
confidence:   # arbiter/critic assigned — supports later eviction
status:       # active | superseded:<id>
admitted_ts:
---
# body: the claim; the conditions under which it predicts its children;
# and the counterexample boundary (where it is known to STOP predicting).
```

### 2c. Decision record (the negative space — the apprenticeship signal)
Written for **every** arbiter verdict, *including rejects*. This is both the
audit of the gate and the future training set for autonomy.

```yaml
ts:
candidate:    # the proposed note, in full
children:     # what it claimed to predict
lift:         # gate score
critic:       # best falsification attempt + whether it landed
verdict:      # accept | revise | reject
rationale:    # WHY — minimal but mandatory. the boundary lives here.
revised_to:   # if revise: the accepted form
```
**Minimum viable rationale:** one line naming *which predictive claim was too
weak / too broad / wrong*. That single line is what a future arbiter learns the
boundary from — without it you store outcomes, not judgement.

## 3. The SINBAD gate (the core — predict, then validate)

A candidate note **N** claims to be the source of correlation over children
**C**. SINBAD's test: N is valid iff it makes its children mutually predictable.
Operationalized as a leave-one-out reconstruction:

**Per candidate N over children C:**
1. **Baseline** — for each child `c`: hide `c`, ask the model to predict its
   salient claim from the *other children only*. Score fidelity 0–1 (LLM-judge
   rubric or embedding similarity). Average → `E_base`.
2. **With-N** — repeat, giving the model **N plus** the other children.
   Average → `E_N`.
3. **Lift** = `E_N − E_base`. Admit only if `lift ≥ τ` (start τ ≈ 0.15, tune).
   Lift is the prediction-error reduction attributable to N — the SINBAD
   convergence signal, ported.
4. **Falsification (critic seat)** — separate pass: instruct the critic to find
   a child, or any corpus episode, that N *mispredicts*. If found, N fails — or
   must narrow its claim/boundary. This manufactures negative examples and
   forces a real boundary rather than an asserted one.
5. **Emit** — candidate + `lift` + per-child scores + the critic's strongest
   attack → to the arbiter (§4). Never auto-admit.

**Honest caveat to encode in the code comments:** this is an *LLM-graded
predictive-reconstruction test inspired by SINBAD*, not literal dendritic
backprop. The signal is soft (model-judged). Treat `lift` as **ordinal** — its
job is to rank/filter and to force every note to survive a prediction it could
have failed, not to be a calibrated loss.

**Guards against premature convergence:**
- Require ≥ k children (k ≥ 3) before a candidate is eligible. Thin bundles
  don't converge.
- Falsification is **mandatory**. A note that faced no counterexample search is
  not admitted.
- Low `confidence` + few children → flagged eligible for eviction on the next
  re-consolidation pass.

## 4. Arbiter loop

Present each surviving candidate compactly: the note, its children, `lift` +
per-child scores, the critic's strongest falsification and why it failed.
Verdict: **accept / revise / reject + one-line rationale** → decision log (§2c),
*including rejects*. Accepts and revised forms flow to write-back.
Make the reject path exactly as cheap as accept, or the rationale won't get
logged — and the rationale is the whole point.

## 5. Write-back (GitOps reconcile loop — your home turf)

- **Desired state of the vault:** notes that predict their children, no orphans,
  nothing `superseded` left active.
- Stage accepted notes in a scratch worktree, run link-integrity + orphan
  checks, land **one commit per pass**. Commit message = consolidation summary
  (candidates / admitted / rejected / bundles touched). Commits are your audit
  log and your undo.
- **Supersession:** a replacement note sets the old note's
  `status: superseded:<new_id>`; the old note stays (history) but leaves the
  active set. **Forgetting is demotion, not deletion** — pruning is a
  first-class op and runs here.
- Rejected candidates → `vault/_rejected/` (the negative set), never discarded.

## 6. Scheduling (the slow loop)

- Queue bundles by summed `surprise` of their episodes since last visit
  (prioritized replay — noisiest first; hiccups lead).
- Run async / offline ("dreaming"). Interruptible per §1.3.
- One pass = one bundle = one commit = one arbiter session. Keep passes small so
  an interrupt costs at most one bundle.

## 7. Build order (concrete steps)

0. **Scaffold.** Create `vault/` (Obsidian), `vault/_rejected/`, and
   `DECISIONS.md` (or `decisions/`). Drop the three schemas (§2) in as
   templates. Confirm the daemon runs in a scratch worktree with atomic-commit
   write-back (§1.2–1.3).
1. **Ingest adapter.** RETROSPECTIVE + PROD_RUN_REPORT → episode records (§2a).
   Verify `surprise` tagging on the hiccups.
2. **Bundler.** Cluster episodes (links / shared entities / embeddings) into
   candidate bundles; draft one candidate note per bundle.
3. **SINBAD gate (§3).** Leave-one-out lift + falsification critic. ← *the
   heart*. Build and test it in isolation, against the existing 13 hiccups as
   fixtures, before wiring anything else.
4. **Arbiter interface (§4) + decision log (§2c).** Reject must be as easy as
   accept.
5. **Write-back (§5).** Reconcile + supersession + rejected-quarantine.
6. **Scheduler (§6).** Priority queue + interruptible loop.
7. *(Later)* **Shadow mode.** A candidate arbiter agent proposes verdicts beside
   the human; log agreement **on the hard cases** (close calls, not easy ones).
   Graduation = sustained agreement on hard cases → cede low-stakes verdicts,
   keep gating the rest. This is only measurable because §2c was logged from
   the start.

## 8. First milestone (smallest thing that proves the gate)

Run steps 0–4 against the **13 existing hiccups only**. Success =
the daemon drafts ≥ 1 candidate note, the gate scores its lift and attempts a
falsification, and you (arbiter) accept or reject it with a logged one-line
rationale. That single end-to-end loop validates *the SINBAD gate sitting
between human and vault* before any scheduling or autonomy is built. Everything
else is scale-up.
