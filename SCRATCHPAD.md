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

## Refactor item 3 — env realignment, REFRAMED + pass 1 LANDED, 2026-06-14 (opus)

**Reframing (user):** env-DRY does NOT mean collapsing dev/prod. Parallel
same-root-structure trees are the *point* of dev→staging→prod — prove pre-prod
before the reputation-exposed prod; collapsing them kills the promotion gate.
Target = **fix accidental coupling/drift in shared code**, **keep intentional,
independently-promotable per-env separation**. DRY lives in shared
modules/templates (define once, instantiate per-env), not in merging instances.
(Full statement in BACKLOG item 3.)

**Pass 1 (de-pin the standalone/DR path) — offline-validated:** the prod
ApplicationSet's `imageParams` already swap `brzl-dev-*`→`brzl-prod-*` per env, so
the `brzl-dev-*` in shared `gitops/infrastructure/*/values.yaml` is a dead GitOps
sentinel (overridden) — NOT a live bug there. It WAS a live latent bug for the two
**standalone** consumers that read the committed files directly (no imageParams):
- `install_ebs_csi.sh` (pass-1 new) now sed-swaps `brzl-dev-k8s`→`${NAME_PREFIX}-k8s`.
- `render_recovery_manifest.sh` + `cluster-recovery.yaml` now carry a third sentinel
  `__PULLTHROUGH_PREFIX__` (→ `$NAME_PREFIX`), so a PROD DR drill pulls the postgres
  image from `brzl-prod-github`, not dev. Verified both prod + dev-default renders.
GitOps `values.yaml` files left **pristine** (avoid GitOps churn under deferred
validation; they're correctly overridden). This is exactly the *right* kind of
env-DRY: make shared code env-agnostic so the SAME code is correct in any env —
which *supports* the promotion model, doesn't collapse it.

**Model B chosen + the terraform layer roll is DONE (offline).** Direction settled
on **model B** (single source per layer + per-env tfvars; gate = separate instances).
SPEC promoted to root as design SoT (§3 reconciled); CLAUDE delegates. All six layers
migrated to `terraform/stack/aws/<layer>/` and `tofu validate` clean:
10-network, 15-kms, 20-security, 30-iam, 40-ecr, 50-compute. Patterns proven:
- driver-composed S3 backend (empty `backend "s3" {}`; bucket from account, key
  `<env>/<layer>/terraform.tfstate`); the gitignored per-env `backend.hcl` is retired.
- env-keyed `remote_state` (`key = "${var.env}/<lower>/terraform.tfstate"`).
- per-env tfvars committed (gitignore exception for dev/prod.tfvars); secret ARNs →
  gitignored `40-ecr/credentials.auto.tfvars` (+ committed `.example`).
- intentional divergences expressed as inputs: 40-ecr toolbox (dev-only build),
  50-compute placement (`public_nodes`) + capacity + the NLB (`enable_public_ingress`,
  count-gated, dev off/prod on — flip to adopt).
Old `environments/{dev,prod}` trees still present (untouched) until the driver works.

**REMAINING for item 3 (next):**
1. **Wire `platform.sh`** to the stack: `cd terraform/stack/aws/<layer>`, compose
   `init -backend-config=...key=$ENV/<layer>/...` (bucket from account), pass
   `-var-file=$ENV.tfvars`. Update `secrets()` to write
   `stack/aws/40-ecr/credentials.auto.tfvars`. (Pre-approved by user; deferred to
   "after the layers".) `00-conductor` is self-contained/dev-only — decide whether
   it also moves to `stack/aws/00-conductor` (no env split) or stays.
2. **Remove** old `environments/{dev,prod}` trees once the driver drives the stack.
3. **Docs:** runbooks (BOOTSTRAP/RECOVERY/TEARDOWN/UPGRADE/ACCESS) + README + an ADR
   for the env-layout + state-backend change (backend.hcl retirement).
Full live validation batched to the one live-pass (greenfield — nothing deployed).

**Later (separate, needs design):** the gitops `clusters/{dev,prod}` ApplicationSet
divergence — reduce the hand-maintained surface WITHOUT losing independent promotion
(git-native; relates ADR-0019 root-app). Not this pass.

## Conductor reframing + multi-account direction — UNDER DISCUSSION 2026-06-15

*(User corrected my "fold 00-conductor into stack/aws" default. Withdrawn — the
conductor is NOT a per-env layer. Direction captured here for durability; SPEC/GUIDANCE
revisions PROPOSED, pending agreement before any write.)*

**The conductor's real role:** a self-contained **CI-runner-like deploy primitive** —
it orchestrates the bootstrap/deploy of *an* environment, constrained only by the IAM
perimeter, sitting where it can see both private-VPC and public network changes. Today
it deploys dev+prod because they share ONE account. It is a SIBLING of
`terraform/bootstrap` + `terraform/identity` (account/perimeter primitives), not a
`stack/aws/<layer>`. → for finishing item 3, leave it at `environments/dev/00-conductor`
untouched; its relocation/refactor is the NEXT major pass.

**Goals for the next major pass (conductor/multi-account):**
1. **n+1 accounts via the same conductor pattern** — deploy stack layers into multiple
   accounts (AWS Org). Model B extends naturally: per-env tfvars gain target account +
   assume-role; per-account state backends (the deferred multi-account state work).
2. **Clean repo delivery + emit/pipe orchestration** — the S3 tree-ship is clunky;
   replace with a scoped git clone (the carried PAT item). And running `platform.sh` as
   a monolith on-box cuts against GUIDANCE §1.8 (emit a flattened stream piped to a bare
   `/bin/bash`). Reconcile: repo is CLONED on the box (terraform/ansible are file-based —
   pipe can't eliminate that); the ORCHESTRATION emits pipeable streams; CI path is
   non-interactive (review moves to the plan/PR), laptop path stays interactive-gated.
3. **Optional cross-account shared resources** — central secrets in one account +
   central ECR images in one account, reachable by all/select env accounts. Selective,
   least-priv resource policies + per-CMK cross-account grants. (ECR nuance: pull-through
   CACHE is account-local — share a RESOLVED-image repo via repo policy, not the cache.)

**Issues to weigh (my honest assessment — detail in chat):** shared-resource
blast-radius/isolation tradeoff (not efficiency — security coupling); ECR cache-vs-repo;
conductor topology hub-and-spoke (one box, cross-account assume-role) vs per-account;
file-on-box vs pure-pipe; multi-account forces the state-model extension model B defers.

**SEQUENCING (user-set):**
1. (now) settle SPEC/GUIDANCE revisions for the above → durable.
2. **FINISH item 3** so it's testable: wire `platform.sh` to `stack/aws` (compose
   backend + `-var-file`), repoint `secrets()` → `40-ecr/credentials.auto.tfvars`,
   remove old `environments/{dev,prod}` trees, runbooks + ADR.
3. **LIVE TEST** the refactored codebase (billable, gated, saved-plan, per-step confirm)
   + **teardown loose ends**: orphaned-resource handling in TEARDOWN, an end-to-end
   AUTOMATED full-teardown sweep (currently missing), + small issues the test surfaces.
4. **Re-assess** the refactoring plan, then run the conductor/multi-account major pass.

## Open considerations

- First bring-up under the `brzl-*` names is unexercised: watch for any
  stragglers the rename sweep couldn't reach (live-account values were all
  retired, but conventions baked into helper scripts deserve a first-run eye).
- **Env-coupling found (item 3):** `ebs-csi/values.yaml` hardcodes `brzl-dev-k8s`;
  prod consumes it too. Recovery path is dev-pinned end-to-end. Park for item 3.

## Session notes

*(detail lives in `aroni/decisions/pass-008..012` + `_candidates/`; not restated
here — Current focus is the live snapshot.)*
