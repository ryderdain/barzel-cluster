# BACKLOG — planned work (shared)

The explicit plan-of-record, edited by **both** the user and the agent. Items
land here when decided, move to [SCRATCHPAD.md](SCRATCHPAD.md) while being
worked, and produce a [RETROSPECTIVE.md](RETROSPECTIVE.md) entry when done and
user-verified.

## Active — the platform, local first

barzel-cluster is a **platform**: a general, secured Kubernetes cluster that
runs on several substrates (k3d, AWS, GCP, DigitalOcean, …) with as few
changes as possible, as the backbone of a CI/CD chain. It does not depend on
any workload (user, 2026-10-14). Vocabulary: [GLOSSARY.md](GLOSSARY.md).
Decisions: [SPEC.md](SPEC.md) §3 and [docs/adr/](docs/adr/). One line per item;
the detail lives in the linked ADR. Q-numbers refer to the design rounds.

Done (verified live; see [RETROSPECTIVE.md](RETROSPECTIVE.md)):

- Passes 0–1: ADR migration; the Bash doctrine in `ryderdain/bash`.
- Pass 2: driver + k3d adapter (2026-10-09; ADR-0021, ADR-0022, ADR-0024).
- Pass 3: Zot beside the cluster, kiesei, warm conductor (2026-10-09; ADR-0023).
- Pass 4: Argo CD, one platform ApplicationSet, fast mode (2026-10-13; ADR-0025).
- Pass 5: ESO 2.12, OpenBao outside the cluster (2026-10-13; ADR-0026).

Order of work (Q120):

1. **Cleanup round** — done 2026-10-14.
2. **5c. Admin portal** (now, branch `pass-5c-portal`) — nginx serves a
   static page and passes each path to its service; TLS `letsencrypt` or
   `local-ca` ([ADR-0028](docs/adr/0028-admin-portal.md)). Q126: a `portal`
   element in the platform ApplicationSet. Q127: host port 443 to a node
   port; Traefik and the service load balancer of k3s turned off.
   Q128–Q137 ([ADR-0036](docs/adr/0036-cert-manager-and-local-stand-ins-for-public-services.md)):
   cert-manager renews; the issuer is the environment's TLS mode;
   `local-ca` on local, `letsencrypt` in pass 8; a CoreDNS stand-in for
   public DNS; `BRZL_PORTAL_HOST` is a value (`local.barzel.sh`).
3. **5d. Example app** — `ryderdain/chofesh` gains a server mode (the
   demo-app's REST API), a small web page and Postgres, and keeps its Go CLI;
   it replaces `apps/demo-app`. The Postgres cluster moves into the app; the
   CNPG operator stays a platform capability. **Keep it short** (user).
4. **6. Logs** — collector, admin and diagnostic Loki, Grafana; UTC
   everywhere; run directories `cluster-<UTC>Z` / `teardown-<UTC>Z`; a header
   line in each run output; API and OpenBao audit logs; `driver.sh <env> state`
   lists (and purges) the state kept outside the cluster
   ([ADR-0027](docs/adr/0027-logs-admin-and-diagnostic-stores.md)).
5. **6a. SSO, local and remote** — Dex + oauth2-proxy in front of nginx; it
   leads to the admin portal, which also works without it (Q108, Q112).
6. **6b. Break-glass mode** — `hold` / `release`; the procedure through the
   conductor; a record of each use; a Grafana reader of the admin store that
   runs only in break-glass mode and also loads the newest cold records
   (Q62–Q65, Q94, Q107).
7. **6c. Cold storage + backups** — the `cold` route; each workload's
   database backups (Q92).
8. **7. `promote platform`** — roll a platform revision one environment at a
   time (Q118).
9. **7h. Remote harness** — a second host (huginn, VMs on sleipnir, or
   OpenStack) to model a shared remote environment (Q116, deferred).
10. **8. Substrate adapters** — one pass for each: first the shared interface
    and AWS, then others. Open items for AWS: the secret-store adapter
    (Secrets Manager) and `gitops/clusters/{dev,prod}/secret-store/`; the
    `letsencrypt` TLS mode (an ACME `ClusterIssuer` with DNS-01 at FreeDNS
    in `gitops/clusters/<env>/pki/`; whether a cloud needs the store copy of
    the certificate; ADR-0036); the
    admin log store (Q96: same product, data in S3); shipping the driver's
    run sheets (Q106); exposing nginx through the Gateway API (Q113); the
    CloudWatch Logs exporter is alpha; the live test of model B
    (`terraform/stack/aws`, never applied); an automated full-teardown sweep;
    `ebs-csi/values.yaml` pins `brzl-dev-k8s` for prod too; the conductor and
    multi-account direction (SPEC §9). Driver credentials (user,
    2026-10-14): `driver/kiesei.sh` mounts only the engine socket and the
    repo and passes `BRZL_*`; no `~/.aws`, no `AWS_PROFILE`. Either mount
    `~/.aws` read-only and pass `AWS_PROFILE` (AWS SSO keeps its session
    cache in `~/.aws/sso/cache`), or export short-lived credentials into
    the container (`aws configure export-credentials`). A wrong-account
    guard: a phase-10 check compares the caller's identity with a marker
    the environment expects (an account alias or a tag, not a committed
    account ID, which would break the derive-at-runtime rule). SSO login:
    an expired session stops the phase with a fix line (`aws sso login
    --profile …`) instead of a credential error in the middle of a run.
11. **9. `promote workloads`** and **`promote all`** (a platform and workload
    change that depend on each other) (Q118). Revisit the Flow diagram in
    ARCHITECTURE §1 then, for the workload repo's branches (user).
12. **Documentation run: the guidebook** (after the last passes; user,
    2026-10-15). One file for each tool or component in `docs/guide/`, for a
    reader who is new to it: the basics, how it works, how this repo uses
    it, with diagrams like those in ARCHITECTURE. For example: Kustomize,
    Helm, OpenTofu, Ansible, Argo CD, OpenBao, ESO, CNPG, Zot, k3d/k3s,
    nginx, the log stack (OpenTelemetry Collector, Loki, Grafana), and each
    operator or controller that the platform adds. **Write a draft when a
    pass first uses a tool or decides to add it**; the run completes them.
    Drafts so far: [Kustomize](docs/guide/kustomize.md),
    [cert-manager](docs/guide/cert-manager.md).
13. **Parked: `driver.sh <env> again <phase>`** — run one phase again on a
    finished cluster, with the conductor install in a phase of its own
    (Q130 b). **Only in case a later pass needs it**; certificate renewal
    does not (cert-manager, ADR-0036).

Standing concerns (check in every pass):

- **GitHub App before leaving local** (Q61). The repo is private. Argo CD on
  local reads it with the read-only deploy key `sleipnir-brzl-deploy`
  (bootstrap source `BRZL_REPO_DEPLOY_KEY`). Replace it with a GitHub App
  credential before pass 7h or 8.
- **Every phase must be safe to run again** (`ryderdain/bash` STYLE §1.11,
  ADR-0022). Review each new phase script for converging commands.
- **Platform-layer portability** (SPEC §3). The platform layer assumes only
  conformant Kubernetes and the adapter's outputs. The legacy SSO edge
  (`gitops/clusters/local/sso/`, Traefik `IngressRoute`) violates it; pass 5c
  replaces its routing, pass 6a its sign-on.
- **ESO in-place upgrades** go one minor at a time and check
  `status.storedVersions` on the four ESO CRDs. Write into `docs/UPGRADE.md`
  in pass 8.
- **Resource budget**: sleipnir 32 GB, huginn 8 GB ([docs/LOCAL.md](docs/LOCAL.md)).
- **`notes/` history scrub** — decision pending with the user (it rewrites
  published history).
- **Port the seed's §1.10** ("a script's claims are part of its contract") to
  `ryderdain/bash` STYLE.md.
- **Operator steps stand out** (user, 2026-10-15): a step the operator must
  do by hand prints in a boxed block on stderr (`operator_step`,
  `driver/lib/phase-common.sh`), for the driver machine's OS
  (`BRZL_HOST_OS`, set by `driver/kiesei.sh`). Port the convention to
  `ryderdain/bash` STYLE.md with §1.10.
- **Before going public on GitHub** (user, 2026-10-14): redraw the ASCII
  diagrams in ARCHITECTURE and README as Mermaid; a cosmetics pass on the
  docs. Last thing, not now.
- **Markdown lint debt**: about 600 older errors (mostly MD013) in SPEC,
  SCRATCHPAD and the runbooks. Clean a file when a pass edits it. Do not
  change RETROSPECTIVE entries without asking.

## Earlier plans (before the local-first refactor; kept as written, review later)

## Active — the major refactor (next barzel session) + aroni assists

**The refactor is the next focus** (items 1–4 below: automation overhaul vs
`notes/GUIDANCE.md`; env DRY/consolidation; multi-account CI). **aroni should drive
it forward** — and the refactor will *generate aroni's next corpus*: every decision,
failure, and fix is an episode. Log them (RETROSPECTIVE / a build ledger) as you go;
consolidate periodically. Watch for the first **co-firing** between existing notes —
that's the event that admits cand-005 and exercises the closed loop for real.

## aroni (consolidation daemon) — machinery complete through 2nd order

Self-contained shared vault at `~/Local/github.com/ryderdain/aroni` (b5744e3): 4
admitted notes, 17 episodes, doctrine (subordination, seam test, intersection test,
co-fire loop — all in METHOD), survival hooks, portable (`init_project`). The
co-fire re-evaluation loop is **closed + enforced** (vault_check + intersections
--work-order). cand-005 (first 2nd-order note) is HELD pending a real co-firing.
Open threads:

- **Next cycle:** ingest the 3 new surprise-0 RETROSPECTIVE episodes; normal pass.
  Also drain the two new **inbox** captures (2026-06-15): the brzl-dev-* standalone-path
  leak (cand-002 evidence) + the instances-vs-source-layout correction (cand-005 framing).
- **Hooks gap (→ aroni BACKLOG, 2026-06-15):** no hook auto-captured the in-session
  correction this session; it took a manual "aronize it". Capture still leans on operator
  memory — the dependency the method exists to remove. Tracked in aroni BACKLOG ("No
  auto-capture of in-session episodes"); sibling of the surprise-mis-tag gap.
- **Fully automating the co-fire re-gate** (vs the current detect+enforce, judge-by-hand)
  — only if it ever proves a bottleneck; the judgment is deliberately human.

- **aroni `lift` is not calibrated across models/sessions** (ordinal, judge-relative).
  A future "re-gate with one judge" pass before any cross-pass score comparison.
  Tabled 2026-06-14. (At second order, lift is already demoted to a sanity check.)
- Seeds: fix-propagation bundle (h3 + a sibling, needs a 2nd episode); cand-005 admits
  on its first demonstrated co-firing; cand-001/003 refinement (arbiter-flagged).

## Planned (user, 2026-06-10 — in intended order)

1. **Automation-methodology overhaul.** Bring all tooling — `platform.sh`
   itself included — into closer adherence with `notes/GUIDANCE.md`. Expect
   multiple passes; this will not complete in one.
2. **Polish `notes/GUIDANCE.md` itself** — as much for the user as for the
   agent.
3. **Environment realignment.** Simplify and consolidate the operational
   paths: bootstrapping on local, dev, and prod.
   **Reframed (user, 2026-06-14):** the goal is NOT to collapse dev and prod into
   one definition — the parallel same-root-structure trees are *the point* of a
   dev→staging→prod split: you prove the pre-production model + code in dev before
   applying it to the reputation-exposed prod. Over-DRYing them away destroys that
   promotion gate. So the real target is the distinction:
   - **Intentional separation — KEEP:** each env is its own independently-promotable
     instance (own state/tfvars, own ApplicationSet apply), so a change lands in dev,
     is validated, then promoted to prod. Real per-env differences (prod private
     nodes + NLB/NodePort, instance sizes, conductor is dev-only) stay explicit.
   - **Accidental coupling/drift — FIX:** shared code that hardcodes one env (the
     `brzl-dev-*` leaks into env-agnostic scripts), and hand-maintained near-duplicate
     files that silently DRIFT (the 2026-06-10 ApplicationSet divergence *bug*). DRY
     belongs in shared **modules/templates** (define once, instantiate per-env), not
     in merging the instances. The divergence bug argues for reducing the
     hand-maintained surface, NOT for one-file-for-both.
   **Direction chosen (user, 2026-06-15): model B** — single source per layer + per-env
   `backend.hcl` + `terraform.tfvars`, driver-enforced backend↔tfvars pairing. Keeps
   separate state + independent apply (the gate); kills drift; fits the per-env-backend
   convention + the item-4 multi-account roadmap. Workspaces (C) rejected (weak state
   isolation, fights multi-account, switch footgun). Per-env structural deltas stay
   explicit: prod-only NLB → `count`/`var.enable_public_ingress`; node placement → vars;
   `00-conductor` stays its own optional standalone layer. **Merge plan pending user review
   before execution** (prototype on `10-network` first, prove the pattern, then roll).
   Full live validation deferred to the batch live-pass; in pass-1 (item 3) the standalone
   DR path was already de-pinned (commit 6941c78).
4. **Multi-account CI design.** Expand the brzl demo model to showcase
   local-dev → infra-test → full-with-app-staging → full-prod across accounts
   — the piece the take-home never reached; have it ready to deliver for a
   similar interview.

## Carried over from the take-home (post-delivery candidates)

Most fold naturally into the numbered items above; tracked here until they do.

- Root-app pattern for the ApplicationSet (close the GitOps seam — ADR-0019
  names the design: include-glob `applicationset.yaml` + `project.yaml`,
  exclude `in-cluster.yaml`). → item 3
- ~~`platform.sh` `operator()` phase: comment claims it installs EBS CSI + gp3,
  body doesn't (open since the A2 drill).~~ → item 1 — **DONE (pass 1, pending live
  verify):** `operator()` now installs EBS CSI + gp3 via the new
  `gitops/bootstrap/install-ebs-csi.sh` (emit-style, renders the SAME committed
  ebs-csi values the ApplicationSet wave 0 uses → can't drift), then asserts the
  gp3 class exists before continuing. RECOVERY.md Step 4 updated.
- ~~Driver hardening: preflight per-layer `backend "s3"` blocks; print "next
  phase: X" on any phase failure.~~ → item 1 — **DONE (pass 1, pending live verify):**
  `preflight()` now asserts every layer declares `backend "s3"` (missing = silent
  LOCAL state); `_run_phases` prints the stopped phase + exact resume command (+
  phases not reached) on any failure, dual-mode (EXIT trap for direct runs,
  return-catch when sourced — no parent-shell trap pollution).
- **Pass-1 also:** renamed `generate-inventory.sh` → `generate-inventory.sh`
  (snake_case rule; all live callers updated, `notes/` history left as-is).
- **Discovered (→ item 3, env-DRY / aroni cand-002 env-coupling):** the shared
  `gitops/infrastructure/ebs-csi/values.yaml` hardcodes the `brzl-dev-k8s`
  pull-through prefix; both dev AND prod ApplicationSets (and now the standalone
  DR install) consume it, so prod's CSI sidecars pull through a `brzl-dev-*`
  repo. The whole recovery path is similarly dev-pinned (`cluster-recovery.yaml`
  → `brzl-dev-github`). Left faithful for now (changing it would diverge the
  standalone path from GitOps); fix env-wide in item 3.
- Generalize local-first state + `init -migrate-state` promotion as the
  bootstrap-from-zero mechanism (and its reverse for retirement) — noted in
  `docs/TEARDOWN.md` §3 / `docs/BOOTSTRAP.md` Phase 0. → items 1, 3
- Conductor repo-read credential (fine-grained PAT, Contents+Metadata) to
  replace the S3 tree-ship one-off. → item 1
- Register this repo's deploy key (public half) before the first GitOps
  bring-up here.
- ECR/Harbor image vulnerability scanning gate (scan-on-push, fail-on-critical).
- Re-enable Alertmanager with a real receiver (one-line flip, needs a target).
