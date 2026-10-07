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

*(2026-10-07, opus — local-first refactor DESIGN SETTLED via a grilling
session; passes 0–8 in [BACKLOG.md](BACKLOG.md). Vocabulary is in
[GLOSSARY.md](GLOSSARY.md). The AWS live test below is DEFERRED — AWS is frozen
until the driver refactor + local are solid.)*

**▶ NOW: pass 1 written, AWAITING USER REVIEW before push.** barzel-cluster
side committed locally (unpushed); `ryderdain/bash` side left UNCOMMITTED in its
working tree (not git-delegated; mixed with the user's own lint edits). Then
pass 2 (driver skeleton + k3d adapter). Open with user: `notes/` history scrub
(feasible: 0 forks/PRs, ~18 SHA refs in memory files + 1 in aroni would break;
needs git-filter-repo + force-push + a GitHub support purge — user must authorize).

Settled design (Q1–Q45, user-confirmed 2026-10-07):

- Local (sleipnir, k3d) = first env of local → dev → prod; harness for cluster-
  structure iteration + future workloads (barzel container; demo-app = smoke).
  k3s on every substrate for now (EKS/GKE/DOKS later, inside an adapter).
- **kiesei** = the one image, two modes: **driver** (*kiesei nahag*, outside
  the cluster: makes/removes clusters, sequences phases, collects outputs, owns
  run-logs `var/run/<env>/<YYYYmmddHHMM>/`) and **conductor** (*kiesei bakar*,
  warm pod in the cluster: runs run-logs detached, writes `.rc`, stdout → Loki,
  idle self-stop). Substrate phases on the driver; cluster phases on the
  conductor; a locus never removes/replaces itself. EC2 conductor retired.
- `.rc` (Q44): the conductor's completion record of one phase; the driver
  collects it into its run-log dir (the canonical copy). Lost with the pod if
  not yet collected → the phase counts as "not done" and re-runs; so every
  phase MUST be safe to run again (idempotent) — a doctrine rule.
- Driver model: emit-style phase scripts + thin driver; emit → run-log → show
  → approve → run; outputs between phases via files. One adapter per
  substrate. Env definition = sourceable plain `VAR=value` list; exported value
  wins + stderr warning; resolved values in the run-log; never flags.
- Approval rule: required for any effect outside the driver, or billable.
- Local substrate: Zot (outside k3d, persistent) = pull-through + push
  registry; OpenBao dev mode (KV + transit), Vault CE fallback via one env
  value; ESO read boundary + per-store write adapters; bootstrap sources all
  arrive as env vars; Loki + Alloy on every substrate; disposable cluster;
  `fast_on`/`fast_off` toggle Argo auto-sync.
- Doctrine: `ryderdain/bash` canonical; emitted streams
  → REVISED 2026-10-08: `{ … }` groups as anonymous functions (reader first),
  check only where re-running a block harms; `.ok` from a per-phase check is the
  verdict, not the exit code (STYLE.md §1.2, §1.11). `CLAUDE.md`
  only refers to `ryderdain/bash`. Platform layer assumes only conformant
  Kubernetes + adapter outputs (Q45).

Previous focus (2026-06-17), superseded for now:

*(2026-06-17, opus — SESSION HANDOFF. User switched to another project; resume here.)*

**▶ RESUME AT: the live test of the refactored stack** (item 3 is code+doc complete,
offline-validated — nothing has been applied to AWS yet; this is greenfield). The live
test is 💸 BILLABLE + cluster-mutating → **GUARDRAILS apply**: surface each command,
saved-plan workflow, per-step confirm, scoped profile; the user drives every apply.

**Item 3 (env realignment → model B) — DONE OFFLINE, committed:**
- All six layers migrated to `terraform/stack/aws/<layer>/` (single source + per-env
  `dev.tfvars`/`prod.tfvars`); 6/6 `tofu validate` clean, `tofu fmt` clean.
- `platform.sh` wired to the stack: `_state_bucket` + `_set_backend_args` compose the
  env-keyed S3 backend (`init -reconfigure`, key `<env>/<layer>/terraform.tfstate`,
  bucket from account); phases pass `-var-file=<env>.tfvars`; `secrets()` →
  `40-ecr/credentials.auto.tfvars`. shellcheck clean.
- Old `environments/{dev,prod}` layer trees REMOVED (kept `dev/00-conductor` + its
  backend.hcl). Docs swept (BOOTSTRAP/RECOVERY/UPGRADE/TEARDOWN/README/SECURITY/SECRETS)
  + **ADR-0020** added (supersedes ADR-0019's per-env-dir layout). SPEC §3/§9 + GUIDANCE
  already carry the design. Last commits: 0d4b171 (docs+ADR) ← ca892f1 (rm trees) ←
  5368045 (driver) ← 9fd3911/fd02e4a/8293125/7488dec (layers).

**THE LIVE-TEST PLAN (next session):**
1. **Bring-up** from the conductor (or laptop apply-role): `ENV=dev bash
   gitops/tools/platform.sh bootstrap` — exercises the composed backend + per-env tfvars
   for the first time. Watch the **first-run-under-new-layout** risks: backend init
   -reconfigure composing the right key; `credentials.auto.tfvars` auto-load in 40-ecr;
   the 40-ecr toolbox build; 50-compute placement + (dev) NLB off. Then prod (`ENV=prod`).
2. **Teardown loose ends** (the user named these): orphaned-resource handling in
   TEARDOWN; build the **end-to-end AUTOMATED full-teardown sweep** (driver teardown →
   leak sweep §4 → finishers §3a — today by hand); fix any small issues the test surfaces.
3. Each fix/finding is an **aroni episode** (log to RETROSPECTIVE on user-verify; the
   aroni inbox already holds Episodes A/B/C from the design phase).
4. On green: write the RETROSPECTIVE entry (item 1 + item 3 graduate, user-verified).

**THEN (separate, post-live-test): the conductor / multi-account major pass** — SPEC §9
is the spec (per-account temporary conductor; clone+pipe delivery; one fine-grained PAT;
optional least-priv cross-account shared-services for a central scan regime; dual-mode
ECR pull-default/push-for-hotfix). Re-assess the plan with the user before running it.

---
*(earlier handoff, 2026-06-14 — aroni machinery + the two-session split; kept for context)*

aroni's machinery is complete through
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

**REMAINING for item 3:**
1. ~~Wire `platform.sh` to the stack.~~ **DONE (5368045):** `_state_bucket` +
   `_set_backend_args` compose the env-keyed S3 backend (bucket from account, key
   `<env>/<layer>/terraform.tfstate`); `_tofu_layer`/`teardown` do `init -reconfigure`
   + `-var-file=<env>.tfvars`; `secrets()` → `40-ecr/credentials.auto.tfvars`;
   `cluster()` re-inits 50-compute per env; preflight reports the derived bucket;
   conductor repointed to `conductor_dir` (legacy, untouched). kubeconfig_setup +
   generate_inventory compute dir → stack/aws/50-compute. Offline-clean.
2. **Remove** old `environments/{dev,prod}` LAYER trees (10/15/20/30/40/50) once
   confirmed — **KEEP `environments/dev/00-conductor` + its backend.hcl** (conductor
   is SPEC §9, not this pass).
3. **Docs:** runbooks (BOOTSTRAP/RECOVERY/TEARDOWN/UPGRADE/ACCESS) + README + an ADR
   for the env-layout + state-backend change (backend.hcl retirement).
Then → **live test** (billable, gated) + teardown loose ends.
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

**Goals for the next major pass (conductor/multi-account) — forks now DECIDED (user 2026-06-17):**
1. **n+1 accounts via the conductor pattern.** Conductor = **temporary, per-account,
   single-purpose IaC distributor / bootstrap engine** (NOT hub-and-spoke — minimal IAM
   footprint, disposable). Model B extends: per-env tfvars gain target account +
   assume-role.
2. **State: tie the conductor to its account's state.** Per-ACCOUNT state bucket (+CMK);
   environments WITHIN an account separated by S3 object key (`<env>/<layer>/…`, e.g.
   dev/stage/prod). Conductor composes the backend from its own caller identity. =
   model B replicated per account (single-account today is the degenerate case).
   Bootstrap state kept separate from targets.
3. **Clean repo delivery + emit/pipe orchestration.** Replace the S3 tree-ship with a
   scoped **git clone**. ONE dedicated GitHub fine-grained PAT carries ALL needed perms —
   `read:packages` (GHCR pull-through) + Contents:read + Metadata:read (clone) — do NOT
   split GHCR from repo (the earlier 403 was an *under-scoped* token, not a multi-purpose
   one; refine GUIDANCE's "scope to job" lesson accordingly). Orchestration emits pipeable
   streams to the conductor's bare bash; repo is CLONED (tofu/ansible are file-based — pipe
   can't eliminate that); CI path non-interactive, laptop path interactive-gated.
4. **Optional cross-account shared resources — least-priv central repo/cache NOW; broader
   distribution next pass.** Rationale is a **unified vulnerability-scanning regime** (one
   scan gate over centrally-cached images), not efficiency. **Trust-direction model
   (who-reads-whom) chosen AT BOOTSTRAP**, recorded in SPEC. ECR distribution options
   (next-pass detail): central pull-through + scan + **promote** + **registry replication**
   to spokes (recommended — scan-gateable); or **cache-chaining** via a custom upstream
   (spokes lazily mirror through the hub). Per-resource CMK cross-account grants.

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
