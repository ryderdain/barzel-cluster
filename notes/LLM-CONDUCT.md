# LLM Conduct Log

This file records where and how an LLM (Claude Code) was used during this work —
kept as an engineering-hygiene log, in the spirit of "use LLMs as you would in
daily work, and document it." It captures the who-said-what of development: what
the model was used for, and where its output was corrected or overridden.

How to read: one dated entry per working session — what the LLM was used for,
and anything notable (decisions it surfaced, where its output was corrected or
overridden, what was done by hand).

---

## 2026-05-29 — Foundations: planning + Terraform scaffolding

- **Used for:** Expanding the Mon Jun 1 "Foundations" plan into a concrete
  design, then scaffolding the repo tree and the Terraform foundation
  (bootstrap state backend, reusable modules, layered dev environment).
- **Notable / human decisions:**
  - State layout chosen by me as **Lee-Briggs layered** (separate state per
    layer, per environment) over a single composed root — for operational
    maturity. The LLM presented the trade-offs.
  - Runtime set to **AWS Graviton (m6g / arm64)**; the LLM flagged the arm64
    knock-on effects (AMI, k3s, container/Helm image arch, ECR pull-through).
  - Conventions seeded from my own `ryderdain/tw-project` (resource `"this"`
    naming, community `terraform-aws-modules/vpc/aws`, `TF_VAR_mycurrentip`
    SSH-lockdown pattern, `eu-central-1`).
  - No `tofu apply` run — scaffolding only, per the billing guardrail.

## 2026-06-01 — Spec + plan iteration; scope additions

- **Used for:** Reviewing the (separately-generated) `PLAN.md`, authoring
  `SPEC.md` as the living end-design spec mapped to `TASK.md`, and rebalancing
  the schedule around a hard **16:00 CEST Wed 10 Jun** delivery.
- **Notable / human decisions:**
  - Two scope additions decided by me to make the submission stand out:
    **(1) constrained-identity deployment** (agents/CI assume least-priv roles
    via OIDC, no static creds) and **(2) operator/CI toolbox container +
    cloud-init bootstrap VM** (session-timeout-proof long ops, no toolchain drift).
  - **IdP decision (cost basis, time vs money):** chose **native AWS OIDC +
    IAM Identity Center** now (feasible same-evening, $0) over self-hosting
    **Ory Hydra** (~1–3 days, portable). Ory kept as the documented portable
    production recommendation — consistent with the repo's ECR→Harbor pattern.
    The LLM produced the time/money comparison; I made the call.
  - **Toolbox delivery:** container + cloud-init VM now; Packer AMI documented
    as the immutable prod path.
  - LLM proposed the "cloud-native-for-demo, portable-OSS-for-prod" narrative
    thread (ECR→Harbor, AWS OIDC→Ory, cloud-init→Packer); I accepted it.
  - Still no `tofu apply` — identity bootstrap (first billable apply) is queued
    for the evening, pending in-chat confirmation.
  - Built `terraform/identity/` (GitHub Actions OIDC provider + scoped
    `tofu-plan`/`tofu-apply` roles); Identity Center left as a documented manual
    prerequisite (not enabled in the account).
  - **My directive:** customer-managed KMS keys only (no AWS-managed default
    keys) — applied to state (bootstrap), ECR, and EBS; LLM wired the matching
    `tofu-plan` KMS grant and flagged the ~$1/mo-per-key cost.
  - Added living runbooks `docs/{BOOTSTRAP,UPGRADE,RECOVERY,TEARDOWN}.md`
    (TEARDOWN suggested by the LLM, accepted; ACCESS/SCALING proposed).

## 2026-06-01 (cont.) — Docs consolidation + secrets-hygiene fix

- **Used for:** Restructuring documentation around a single front-door README,
  authoring the `ACCESS.md` onboarding runbook, and a git secrets-hygiene sweep.
- **Notable / human decisions:**
  - **My directive:** the **top-level `README.md` is the primary doc**; removed all
    per-directory leaf READMEs (cognitive noise) and folded their content into the
    README / runbooks / `SPEC.md`. Recorded the convention in `CLAUDE.md` so it
    survives compaction. LLM migrated the load-bearing content and fixed dangling links.
  - **Scaling + backups are automated** (HPA / CNPG `.spec.instances` / Terraform
    node count; CNPG→S3 continuous+scheduled) and documented in the README — I
    declined a separate `SCALING.md` runbook. `ACCESS.md` written as a runbook.
  - **Secrets leak caught by the LLM:** `environments/dev/backend.hcl` was tracked
    from the initial commit, so `.gitignore` couldn't hide it and the real account
    id was staged to ship. Fixed via `git rm --cached` (working copy retained) +
    committed `.example` templates. Verified `terraform/identity/` real
    `backend.hcl`/`terraform.tfvars` are ignored before the whole-tree commit.
  - Moved this log to the repo root (`LLM-CONDUCT.md`) alongside the README.
  - Still no `tofu apply` — bootstrap apply remains gated on in-chat confirmation.

## 2026-06-02 — Live infra bring-up, Ansible roles, operator toolbox

- **Used for:** First billable applies (dev layers `10→50` under the assumed
  `brzl-tofu-apply` role), writing the Ansible `base`/`security` roles + the
  inventory generator, and building the operator/CI toolbox + bootstrap-VM
  containers.
- **Notable / human decisions:**
  - **My directive:** run *everything* under the assumed least-priv role; only
    `terraform/identity/` perm changes run as my own principal, and blockers
    loop back to widen the role. The constrained-identity model held — no
    loop-backs needed.
  - **Spot reclaim, real-world:** the `capacity_type=spot` bring-up was reclaimed
    within minutes (eu-central-1 pressure). I switched to **on-demand**; the
    toggle the LLM had built did its job. Good signal for the write-up.
  - **SSH key handling corrected by me:** the LLM's first instinct was a
    user-supplied key var; I redirected it to my `tw-project` TF-generated
    keypair pattern (`tls_private_key`→`aws_key_pair`→`local_sensitive_file`),
    owned by the `50-compute` layer.
  - **EBS CMK cost:** I flagged that the per-iteration CMK churn costs ~$1 each
    replay; shortened the deletion window to 7d as a stopgap and logged "move the
    CMK to a persistent layer" to the backlog. Teardown gated on my question first.
  - **Toolbox base + pins (my call):** bump to `python:3.14-slim-trixie` and pin
    Python/Debian to ~2030 EoL series — the LLM had pinned `ansible-core` 2.20
    against bookworm's Python 3.11 (incompatible); the live build caught it.
  - **Container user rename (my call):** `operator`→`opagent` (reusable beyond
    this project; also sidesteps a Debian system-group collision the build hit).
  - **Supply-chain (my directive):** vendor + GPG-verify AWS's signing keys
    (aws-cli, and later the session-manager-plugin) rather than TLS-only trust;
    the LLM had defaulted to "pin + document the gap" for the plugin until it
    found AWS publishes a `.sig`.
  - Bash discipline enforced: I challenged a `set -eux`; confirmed it's justified
    only in Dockerfile `RUN`s, with explicit return-code checks in standalone
    scripts (per `CLAUDE.md` / BashPitfalls).

## 2026-06-02 (cont.) — SSM keyless node access: design, build, live test

- **Used for:** Designing and building **SSM Session Manager** node access,
  then a full live end-to-end test (bring-up → bootstrap → teardown).
- **Notable / human decisions:**
  - **Rejected the LLM's over-engineered default (key correction):** the LLM
    proposed the Ansible `aws_ssm` connection plugin, which needs an S3
    file-transfer bucket, and even spun up a "where should the bucket live"
    decision. I pushed back — SSM Session Manager needs no bucket — and had it
    explain the mechanic (the bucket is the *plugin's* file-copy hack, not an SSM
    requirement; ArgoCD never touches nodes; SSM connectivity uses no customer
    S3). We chose **SSH-over-SSM** (ProxyCommand tunnel): no bucket, ordinary
    Ansible semantics, lower cognitive overhead for junior operators. The key
    stays as break-glass only.
  - Threaded the change into existing layers (no new layer): `:22` ingress made
    optional and set off in `20-security`; inline SSM policy on the node role in
    `30-iam`; inventory keyed by instance-id; `session-manager-plugin` added to
    the toolbox (GPG-verified against AWS's distinct plugin key, which I supplied).
  - **Live test caught three LLM bugs that only surface by running it:**
    (1) ssh tripped `MaxAuthTries` because ssh-agent keys were offered first →
    added `IdentitiesOnly=yes`; (2) the `yaml` stdout callback was removed in
    community.general 12 → switched to the builtin `result_format=yaml`;
    (3) the `base` role assumed `systemd-timesyncd`, but the AMI uses chrony.
  - **Cloud-agnostic NTP (my catch):** when the LLM moved to "just enable
    chrony," I caught that chrony was syncing to AWS's `169.254.169.123` (a
    cloud-init drop-in). Per TASK.md's provider-neutral goal I directed: drop the
    AWS source, disable cloud-init's NTP module, and use the vendor-neutral
    `pool.ntp.org`. Verified live (no `169.254.x` source).
  - **Result:** SSH-over-SSM proven with zero inbound `:22`; `base`+`security`
    roles green and idempotent; sshd hardening applied without lockout.
  - **Teardown discipline (my directive):** retain all KMS keys (cheaper to keep
    than replay). The LLM did an **instances-only `-target` destroy**, leaving the
    EBS CMK `Enabled` (first iteration with no CMK churn); NAT/network/state kept.
  - Guardrails honored throughout: every billable apply/destroy used the
    saved-plan workflow and a per-step in-chat confirmation.

## 2026-06-03 — k3s HA role, docs reorg, operator toolbox + iteration tools

- **Used for:** Authoring the `kubernetes` Ansible role (k3s HA, 3-server
  embedded etcd) and live-verifying it end-to-end; reorganizing the docs
  (delivery-facing `docs/ARCHITECTURE.md` + ADR log, SPEC.md demoted to internal
  gitignored scratchpad); making the operator toolbox functional in-cluster and
  baking its build into the 40-ecr layer; generating `gitops/tools/` helpers.
- **Notable / human decisions:**
  - **SPEC↔ARCHITECTURE split (my directive):** "SPEC iterates, ARCHITECTURE
    curates" — SPEC.md stays the internal scratchpad where decisions land first;
    `docs/ARCHITECTURE.md` is the curated delivery doc with a running ADR log.
    SPEC.md gitignored alongside PLAN/TASK; git presence is a signal to LLM.
  - **EKS nuance I added to ADR-0001 / "Why k3s":** a core value-add of the original vendor is
    running secure workloads in public cloud *even on managed control planes*
    (EKS control-plane nodes are ostensibly patchable) — so managed k8s isn't
    categorically off the table. k3s still the right call here (time + it's a
    plausible target for its own software). Flagged as a revisit
    consideration rather than a closed door.
  - **Live test caught three LLM bugs that only surface by running it:**
    (1) the install guard checked `k3s --version`, but the role vendors the
    binary *before* the check, so install was always skipped → switched to
    testing for the systemd unit; (2) `command` module word-split the
    `jsonpath={range …}` form; (3) shlex stripped the quotes around `"Ready"`
    → fixed both with the `argv` list form. Verified 3/3 Ready + idempotent.
  - **Toolbox baked into IaC as a self-validating check (my directive):** the
    40-ecr apply builds + pushes + verifies the toolbox image via a
    `terraform_data` local-exec, so a green apply *is* the e2e proof. Content-
    addressed tag (sha256 of build inputs) because ECR repos are IMMUTABLE — a
    rolling `latest` could only be pushed once. Image source for in-cluster use:
    ECR + an auto-refreshed (~12h) pull-secret bound to a `toolbox` SA.
  - LLM caught `kubectl run --serviceaccount` was removed in newer kubectl →
    switched to `--overrides` for `serviceAccountName`.
  - **Naming convention I set:** snake_case for script filenames *and*
    variable/identifier names across all code, unless a stronger language
    convention governs (Go MixedCaps, k8s manifest keys camelCase). Recorded in
    CLAUDE.md; backlog item to rename `generate-inventory.sh`.
  - **EBS CSI re-sequenced (my choice):** deliver EBS CSI + gp3 default
    StorageClass as a GitOps wave-0 infrastructure Application under ArgoCD, not
    a standalone install — honors the "delegate k8s config to ArgoCD" decision.
  - Guardrails honored: billable applies used the saved-plan workflow with
    per-step in-chat confirmation; git commits left for me to finalize + push.

## 2026-06-03 (cont.) — ArgoCD app-of-apps scaffolding + ECR pull-through extension

- **Used for:** Scaffolding the GitOps layer — ArgoCD app-of-apps (root +
  `brzl-dev` AppProject + sync-wave-ordered child apps), the wave-0 EBS CSI +
  gp3 default StorageClass app, ArgoCD self-management, the one-time Helm
  bootstrap script + repo deploy-key `.example`, and extending the ECR
  pull-through cache (quay.io + ghcr.io) with the node-role import perms.
  Docs: ADR-0013, ADR-0008 update, SPEC decisions 7–10, README doc-map.
- **Notable / human decisions (I chose, via the question prompt):**
  - **Private-repo auth = read-only GitHub deploy key** (not a PAT, not public)
    — narrowest blast radius; the private key stays in a gitignored Secret.
  - **Extend ECR pull-through to quay/ghcr now** (vs. pulling upstream + deferring)
    — keeps the "images via ECR" supply-chain story whole; cost is per-upstream
    Secrets Manager credential secrets + create-on-pull IAM perms, surfaced as a
    gated apply.
  - **ArgoCD bootstrapped via Helm then self-manages** (vs. raw manifests) — argo
    upgrades become git diffs.
- **LLM-surfaced gotchas I had it design around:**
  - Pull-through create-on-pull needs `ecr:CreateRepository` +
    `ecr:BatchImportUpstreamImage` on the *pulling* principal — the node role only
    had read perms (never bit us yet because k3s installs via Ansible, not ECR).
    Scoped the new perms to the `brzl-dev-*` cache prefixes.
  - quay.io **and** ghcr.io both require authenticated pull-through (ghcr even for
    public packages) — mirrored the existing credential-ARN-gated Docker Hub rule.
  - **Account-id-in-git tension:** ArgoCD reads manifests only from git, but the
    ECR host carries the account id (our hygiene rule gitignores account-bearing
    values). Resolved with a `__ECR_REGISTRY_HOST__` sentinel (account-agnostic
    deliverable) resolved via `helm --set` at bootstrap; documented the clean prod
    fixes (ApplicationSet cluster-generator value, or Harbor's account-less host).
- **Scope / guardrails:** pure scaffolding — *no* billable apply run. The
  Terraform pull-through/IAM changes (`tofu fmt` clean) and the one-time helm
  install are gated behind explicit confirmation + the upstream credential
  secrets. Helm chart versions pinned (argo-cd 7.7.0, aws-ebs-csi-driver 2.37.0);
  bootstrap script shellcheck-clean, snake_case per CLAUDE.md.

## 2026-06-03 (cont. 2) — local kubeconfig tool + secret-store decision

- **Used for:** A `gitops/tools/kubeconfig_setup.sh` helper (reuse the fetched
  admin creds, re-resolve the current primary endpoint via `tofu output`, rename
  to an `brzl-dev` context, merge into `~/.kube/config` with a backup); and
  reworking the GitOps secret/config story.
- **Secret-store course-correction (human):** I briefly asked to keep the
  quay/ghcr creds + ECR host in **GitHub repo Secrets** (GitHub as source of
  truth), then withdrew it as "wrong-headed." The LLM had surfaced the blockers:
  GitHub repo Secrets are **write-only** (only readable inside a GitHub Actions
  run), and ECR pull-through's `credential_arn` **can't** reference them anyway.
  Landed on: **Secrets Manager** for the pull-through creds (required; prefix
  `ecr-pullthroughcache/`), **SSM Parameter Store** for the non-secret ECR host
  (`/brzl-dev/ecr/registry_host`), and a general "Parameter Store for non-secret
  config when reasonable" preference.
- **Built around it:** SSM param in the ecr module; bootstrap resolves the host
  from Param Store (STS fallback); `create_pullthrough_secrets.sh` emit-commands
  helper that references the tokens as runtime `$VAR`s so a dry run never prints
  them (leak-checked). Documented the narrow ADR-0006 exception (these upstream-
  token secrets default to the AWS-managed Secrets Manager key; a CMK would need
  an ECR-service decrypt grant).
- **Guardrails:** still no billable/mutating run — Secrets Manager creation,
  30-iam/40-ecr applies, and the helm bootstrap remain gated on confirmation +
  real credentials. `tofu fmt` clean, ecr module `validate` passes, both new
  scripts shellcheck-clean.

## 2026-06-03 (cont. 3) — node→ECR auth + ArgoCD up (live, billable)

- **Used for:** First live execution of the GitOps path: applied `30-iam`
  (pull-through import perms) and `40-ecr` (cache rules + SSM host param) via the
  saved-plan workflow, generated + registered the ArgoCD deploy key, added a
  kubelet **ECR credential provider** to the Ansible k3s role and ran it, then
  helm-installed ArgoCD pulling its image through ECR — proving the chain.
- **Standing permission set (human):** `tofu plan` is now pre-authorized (read-
  only); apply/destroy + other mutations stay gated. Saved to memory.
- **Two AWS realities the run surfaced:**
  - **quay.io pull-through needs NO credential** — ECR rejected the credential_arn
    with `UnsupportedUpstreamRegistryException` ("doesn't require authentication").
    Reworked the quay rule to be credential-free (like registry.k8s.io); the
    operator's quay robot account turned out unnecessary (ghcr still needs auth).
    Good reminder to verify per-upstream auth rather than assume uniformity.
  - **Nodes didn't authenticate to ECR at all** — the toolbox had masked this with
    a manual pull-secret. Pods couldn't have pulled ECR-cached images. Fixed
    properly with the kubelet credential provider (vendored `ecr-credential-provider`
    v1.31.7, pinned sha256 per arch, instance-profile auth, no rotating secrets),
    wired via `/etc/rancher/k3s/config.yaml` kubelet-arg + a **throttle:1 rolling
    restart** that blocks on each node's `/readyz` to keep etcd quorum.
- **Validated end-to-end:** all 6 ArgoCD pods Running; image resolves to
  `…/brzl-dev-quay/argoproj/argocd:v2.13.0`; the `brzl-dev-quay/argoproj/argocd`
  cache repo was auto-created on first pull (create-on-pull perms confirmed).
- **Deferred (tomorrow):** GitHub wiring — commit/push `gitops/`, apply
  deploy-key Secret + AppProject + app-of-apps root, resolve the host sentinel,
  watch EBS-CSI/gp3 then CNPG sync. ArgoCD is a plain helm release until the
  self-manage app adopts it.
- **Process notes:** ansible-lint clean (production profile); the deliberate
  `shell` restart is `# noqa`'d with a quorum-safety rationale. Unused quay
  Secrets Manager secret left as a trivial teardown-sweep note.

## 2026-06-04 — EBS-CMK migration, demo app, ESO secret projection, local-dev decision

- **Used for:** Four threads, all under the assumed `brzl-tofu-apply` role where
  AWS was touched.
- **EBS-CMK state migration (live, no resource change):** `state rm` of the EBS
  CMK + alias from `50-compute` and `import` into the persistent `15-kms` layer
  (`module.kms_ebs`), completing the ADR-0006 move. Verified plans: `15-kms` = 9
  add / 1 in-place (deletion_window 7→30) / **0 destroy**; `50-compute` = no key
  destroy. Physical key `4805a479…` untouched (no re-encrypt). Synced `UPGRADE.md`
  and PLAN; `15-kms apply` is now an ordinary bring-up step, no surgical targeting.
- **Demo REST app (`apps/demo-app`):** LLM-drafted **Go + pgx** on
  **distroless/static:nonroot**, arm64, 18.7 MB. `/healthz` (no DB) + `/readyz`
  (DB ping + schema-ready flag), `GET/POST /items`, idempotent schema with
  capped-backoff retry, graceful SIGTERM drain, slog JSON. **Verified by running
  it** — natively *and* as the built container against a throwaway PG17: full
  read/write round-trip, correct 200/201/400/503, and the startup retry caught a
  real cold-DB race live. `go vet` clean, shellcheck-clean `build_push.sh`.
- **Secret projection via External Secrets Operator (ADR-0014):** decision made
  *with the human* (own-`demo`-namespace + ESO over same-namespace / reflector /
  synced-secret). Built the wave-1 ESO app + a least-priv reader SA/RBAC →
  `ClusterSecretStore` → `ExternalSecret`. **Caught an LLM-plausible bug by
  reasoning about DNS:** CNPG's `uri` embeds the short `pg-rw` host (unresolvable
  cross-namespace) — reworked ESO to *template* the DSN with the FQDN +
  `sslmode=require`. De-risked offline with `helm template` (chart 0.10.7 renders,
  values keys honored, serves `v1beta1`).
- **Local-dev (k3d) viability — analysed, deferred by decision (ADR-0015):**
  judged it viable + cheap (k3d = same k3s, `local-path` already a documented
  lever) but a *built+tested* path would eat the delivery buffer; recorded
  design-only now (ADR + overlay-ready manifests), build is post-delivery /
  spare-buffer-only-if-ahead. Human chose the deferral.
- **Docs/drift:** ADR-0014/0015, SPEC §7.12–13 + changelog, new `docs/SECRETS.md`
  credential inventory (+ README doc-map + a CLAUDE.md living-docs sync rule so
  SECRETS.md doesn't drift). The Go/distroless stack was deliberately **not**
  recorded in SPEC (human's call — app is incidental to the infra story).
- **Guardrails honored:** nothing billable applied; demo image **not** pushed
  (ECR login is a bring-up step); gitignored working files (`SPEC/PLAN/CLAUDE`)
  excluded from the commit; commit staged + message drafted for the human to
  finalize.
- **One bring-up check banked:** the `ExternalSecret` assumes `pg-app` keys
  `username`/`password`/`dbname` — confirm against the live CNPG secret at the
  "inspect connection secret" step before relying on them.

## 2026-06-04 (PM) — Live bring-up: full stack on AWS, end-to-end verified

- **Used for:** Driving the live bring-up under my step-by-step gating — KMS
  migration, all six OpenTofu layers, Ansible k3s HA, the ArgoCD/ApplicationSet
  GitOps phase, demo-app image push, and the end-to-end API test — plus
  diagnosing/fixing four issues the first live run surfaced.
- **Outcome:** All six ArgoCD apps Synced/Healthy by wave; CNPG Postgres 3/3 HA
  on EBS gp3; demo-app read/writes proven (`POST`/`GET /items`, rows confirmed
  in the `pg-1` primary). ADR-0016 (account-id-free ApplicationSet injection)
  **validated live** — the CMP fallback is retired.
- **Issues the LLM diagnosed + fixed (all gated through me, each its own commit):**
  - **ApplicationSet `name` collision:** in a `matrix`, the `clusters` generator's
    `name` (cluster name) shadowed the `list` element's `name` → all apps
    collapsed to one + the `eq .name "…"` branches died silently. Re-keyed to
    `appName`. The LLM traced this from the duplicate-`Application` error.
  - **ArgoCD self-prune cascade (the sharp edge of the above):** the mis-named app
    carried the wave -1 self-manage element; pruning it cascade-deleted
    `argocd-cm`/RBAC/SAs. Recovered by `helm upgrade --install` + controller
    restart (stale SA tokens) — LLM reasoned out the 401-Unauthorized → recreated-SA
    token-invalidation chain rather than rebuilding.
  - **EBS CSI sidecars:** repository-only override left the chart's `-eks-1-31-7`
    EKS-distro default tags, which 404 on the registry.k8s.io pull-through. Pinned
    plain upstream tags (verified each resolves through the cache before committing).
  - **ghcr.io pull-through (the planned "CNPG block"):** the `brzl-dev-github`
    rule didn't exist — ECR mandates a Secrets Manager credential for ghcr. **I**
    minted the `read:packages` PAT and ran the secret-creation + `40-ecr` apply
    myself (kept the token out of the agent transcript); the LLM took the ARN from
    there. Unblocked CNPG operator, external-secrets, AND the Postgres data image.
  - **demo-app `runAsUser`:** `runAsNonRoot` with no numeric uid fails on
    distroless:nonroot; pinned `65532`.
- **Recurring operational note captured:** an auto-sync app past its retry budget
  won't re-sync on hard-refresh — force via a `kubectl patch … operation` (now in
  RECOVERY.md).
- **Guardrails honored:** every billable/mutating step (tofu applies, the ghcr
  secret + 40-ecr re-apply, ArgoCD bootstrap, image push) was previewed and
  gated; I finalized + pushed every commit; account id never entered git.
- **Docs synced:** ADR-0016 "Validated live" addendum, RECOVERY.md ArgoCD
  control-plane recovery section, this entry. SECRETS.md/BOOTSTRAP.md already
  anticipated the ghcr step — no drift.

## 2026-06-04 (eve) — Observability + demo-app evolution (Sefaria search)

- **Used for:** Adding the monitoring stack and the app-level visibility the
  challenge wants, then evolving the demo-app so the dashboards show real traffic.
- **Monitoring (ADR-0017):** wave-1 kube-prometheus-stack via the ApplicationSet,
  Alertmanager trimmed, CNPG scraped (PodMonitor), CloudNativePG Grafana dashboard
  (gnetId 20417). Account-id hygiene reused ADR-0016 with a single
  `global.imageRegistry` injection (new `hostParams`); **all ~9 chart images
  verified through `helm template`** (→ `<host>/brzl-dev-*`, zero leaks) before
  apply. Needed the **Docker Hub pull-through** (Grafana + curl) — the human minted
  the token + ran the secret/40-ecr apply (token kept out of the agent transcript).
- **Three live UI bugs caught by exercising it, each root-caused not patched-over:**
  (1) ArgoCD UI wouldn't load — server runs `insecure`/HTTP, so the helper forwarded
  the wrong port; (2) Grafana login 401 — the chart's `adminPassword` default is a
  `randAlphaNum` that regenerates each render, so it drifted from the DB → switched
  to a bootstrap `grafana-admin` Secret via `existingSecret` (repo's no-secrets-in-git
  posture) + persistence off; (3) ApplicationSet `name` collision recurrence avoided.
  Also fixed the AppProject sourceRepos whitelist for the new chart repo.
- **demo-app → Sefaria search web app:** at the human's direction, **borrowed the
  search client from their `chofesh` CLI** (pure-stdlib, copied as an internal pkg).
  Added a server-rendered search UI, persisted searches + results + an outbound-call
  log to CNPG (instrumented `http.RoundTripper`), and app-level Prometheus metrics
  (+ ServiceMonitor). Smoke-tested locally (Postgres + a live search) before the
  image build; verified live (both pods scraped `-> up`), then a 45-search burst lit
  up the dashboards (48 searches / 253 results / 48 api_calls persisted).
- **Guardrails honored:** every mutating step (40-ecr apply, image push, ApplicationSet
  re-apply, syncs) previewed/gated; the human finalized + pushed every commit; no
  account id or token in git; `helm template` + local smoke tests de-risked offline.

## 2026-06-04 (night) — Teardown/DR test, state-bucket fix, local-dev (k3d) built

- **Used for:** Planning an operator-SSO gateway, then (on the human's redirect)
  pivoting to build the **local-dev environment** and run a full **teardown as a
  DR test**.
- **SSO gateway — planned, deferred to stretch:** designed the full portable SSO
  gate (Dex→GitHub + oauth2-proxy forward-auth + Traefik + Terraform NLB +
  cert-manager/Let's Encrypt + kube-API OIDC + RBAC tiers), establishing it needs
  **no IRSA** so it doesn't conflict with local-dev. The human chose to bank it as
  a stretch goal and prioritise local-dev — plan retained.
- **State-bucket fragility — caught + fixed at the source (human-directed):** a
  teardown `plan -destroy` failed `NoSuchBucket` because the `terraform_remote_state`
  data sources read `var.state_bucket` from a per-run `TF_VAR` I'd been hand-exporting
  and dropped. The human's principle: "if you can lose it, so can any operator." Fixed
  by **deriving the bucket from `data.aws_caller_identity`** in each `remote_state.tf`
  — no env var, account id still out of git. Noted in CLAUDE.md + memory.
- **Full teardown as a DR test:** captured a fresh pre-teardown CNPG backup +
  recorded the dataset acceptance target in RECOVERY.md, then destroyed everything
  below `15-kms` (`10`–`50`, including `40-ecr` — force-emptied the repos), keeping
  only the persistent backups + CMKs. Cost-leak swept the orphaned CSI EBS volumes;
  confirmed no NAT/EIP/ENI/pull-through residue. The dataset now rides entirely on
  the S3 backups (restore half is the A2 bring-up).
- **Local-dev (k3d) — built, ADR-0015 flipped:** a `gitops/clusters/local` kustomize
  overlay (upstream/imported images, `local-path`, backups+monitoring off, single
  Postgres) + an emit-commands `k3d_up.sh`, applied via `kubectl apply -k` (not the
  ECR-coupled ApplicationSet). Resolved one design point on contact — images go
  **upstream/`k3d image import`**, not "retain ECR", since the host-injection is
  AWS-only. Verified end-to-end **first try**: CNPG on local-path, ESO projection,
  demo-app search read/writes the local Postgres with `AWS_PROFILE` unset.
- **Guardrails:** the full teardown was previewed and run on the human's single
  "one go" approval; commits staged + drafted for them to finalize/push.

## 2026-06-04 (late) — Operator SSO gateway authored (Dex, local-first)

- **Used for:** Designing + authoring the full **operator-SSO gateway** on the
  local k3d cluster (ADR-0018) from the approved `composed-percolating-lemon.md`
  plan — one GitHub-backed sign-on in front of the cluster web UIs *and* the
  kube-API, with role tiers, real Let's Encrypt certs, portable to AWS.
- **What was produced:** `gitops/clusters/local/sso/` (Dex→GitHub issuer; three
  per-host oauth2-proxy reverse-proxy gates; Traefik IngressRoutes + http→https
  config; cert-manager LE issuers + wildcard `*.sso.barzel.sh` via the FreeDNS
  DNS-01 webhook; lean kube-prometheus-stack values + a stable Prometheus Service;
  kube-API OIDC RBAC), the `k3d_up.sh --with-sso` orchestration, `create_sso_secrets.sh`,
  and the docs (ADR-0018 + ACCESS/SECRETS/LOCAL/README). shellcheck + YAML clean.
- **Notable / human decisions:**
  - **Personal GitHub (no org)** chosen by the human → Dex emits no group claims,
    so I keyed the tiers on the **operator email** (oauth2-proxy allowlist + RBAC
    subject) and documented the org/team-group mapping as the one-line promotion.
  - **TLS on the human's own domain** `barzel.sh` (DNS on afraid.org) — I verified
    the FreeDNS DNS-01 webhook is viable for an owned domain (the wildcard limit
    only bites shared `*.afraid.org`), so the local build rehearses the *exact*
    cert-manager/DNS-01 path AWS will use; sslip.io+self-signed kept as fallback.
  - **Design correction mid-build:** dropped the planned Traefik forward-auth
    middleware tier (it 401s without redirecting to the IdP) for **per-host
    oauth2-proxy in full reverse-proxy mode** — the auto-redirecting, battle-tested
    pattern; also removed the need for any Traefik cross-namespace flag.
  - **k3d issuer-reachability** (the flagged risk) handled by giving the in-node
    API server the serverlb container IP for the Dex host via a post-create
    `/etc/hosts` patch, while oauth2-proxy skips OIDC discovery and reads token/JWKS
    over in-cluster Service DNS.
- **Pending (human):** GitHub OAuth App + FreeDNS cred + `/etc/hosts` are the
  one-time prereqs; live bring-up + 1–2 iterations to follow. All secrets flow in
  as env (never committed); commits staged + drafted for the human to finalize.

## 2026-06-09 — Live from-zero AWS bring-up + validation-driven hardening (conductor)

- **Used for:** Navigating a complete **from-zero AWS bring-up driven from the
  conductor** (account bootstrap → conductor → secrets → Terraform layers →
  Ansible/k3s HA → GitOps → seed) — the human drove every gated apply, I diagnosed
  and fixed each edge issue surfaced live — then finalized the Upgrade write-up (4d).
- **What was produced (every fix found by running the real path, not review):**
  - **20-security:** auto-detect the admin /32 via an `http` data source (dropped
    `TF_VAR_mycurrentip`) — works from the conductor (its public egress IP) or a laptop.
  - **EBS CMK ↔ EC2 Spot SLR:** the EBS key policy now grants `AWSServiceRoleForEC2Spot`
    (the one principal IAM can't reach), so spot nodes attach their encrypted root
    volume; the SLR is resolved-or-created in `15-kms` (`modules/kms` gained
    `service_grant_principals`).
  - **Conductor cloud-init:** pre-create `ssm-user` in the `docker` group (SSM creates
    the user lazily, *after* the old runcmd usermod), install `session-manager-plugin`
    (Ansible reaches the nodes over SSH-over-SSM), install `k9s`.
  - **platform.sh:** fixed `printf '---'` (parsed as options — broke every preview
    header); the `gitops` phase now creates the `grafana-admin` Secret before the
    monitoring wave (was a silent manual prereq → Grafana stuck `CreateContainerConfigError`).
  - **Tooling:** `ui_forward.sh` prints the laptop-side SSM port-forward commands when
    run on the conductor; `seed_demo_data.sh` gained a self-contained `pf` mode
    (backgrounded forward, seed, torn down on exit); `create_pullthrough_secrets.sh`
    silenced the expected `ResourceExistsException` noise (the create-or-update was fine).
  - **Docs:** README/BOOTSTRAP spell out the evaluator-staged inputs (the ArgoCD repo
    deploy key especially — gitignored, NOT shipped to the conductor); SECRETS records
    the EBS-CMK Spot-SLR grant as the documented exception to IAM-only delegation;
    UPGRADE.md grounded in what the bring-up validated.
- **Outcome:** 7/7 ArgoCD apps Synced/Healthy (gp3 default; CNPG HA primary + 2
  streaming replicas; ESO projection; demo-app), data path seeded end-to-end
  (app→Sefaria→Postgres). The conductor execution-locus model (no repo credential;
  tree shipped via S3 + `brzl-fetch`) held up; spot capacity was unavailable in-region
  so the run used on-demand.
- **Notable / human decisions:**
  - Chose the **full validation from the conductor**, not the laptop shortcut.
  - On spot capacity-not-available, ran **on-demand** for the validation but had me wire
    the Spot-SLR grant so the spot path is robust for future cheap-iteration runs.
  - Flagged **grafana-admin into the `gitops` phase**, **k9s** on the toolbox,
    **`ui_forward` conductor→laptop chaining**, and a **self-contained seeder** — folded in.
  - Raised the **evaluator-handoff** gap (gitignored in-cluster secrets aren't shipped) →
    we documented them as pre-stage requirements rather than auto-provisioning (a
    Secrets-Manager-backed provisioning step noted as a follow-up, not a blocker).
  - On the Upgrade write-up: confirmed **no live upgrade test is needed** — the bring-up
    exercised every mechanism the upgrade paths use; only the version bumps (CNPG minor,
    k3s) are unrun, and those are the controllers' standard rolling behaviour.
- **Guardrails:** every billable apply/destroy gated + saved-plan; commits staged +
  drafted for the human to finalize/push; GUIDANCE.md kept untracked. Teardown to follow.

## 2026-06-10 — Delivery day: doc-truth alignment, time table, prod env built + validated live

- **Used for:** An interviewer-style evaluation of the repo against TASK.md, then
  closing what it found: docs aligned with the (better-than-documented) A2 reality,
  the required time table, and — the day's centerpiece — **authoring and live-validating
  the prod environment** (private-subnet nodes, NLB-only ingress; ADR-0019), human
  driving every gated step, LLM navigating. A hiccup ledger (gitignored
  `PROD_RUN_REPORT.md`) recorded every failure with its fix and doc destination.
- **Evaluation catches (LLM, then fixed together):** the README claimed an HPA that
  didn't exist (human reworded — honest "not implemented"); LEADERSHIP claimed "In CI
  today" with no CI (human reworded); README/RECOVERY said the restore drill was
  pending when it had **passed 2026-06-08** (LLM aligned both); the required time
  table was missing (LLM reconstructed `TIMETABLE.md` from session telemetry + git
  history); prod was `.gitkeep` stubs (became today's build).
- **Prod bring-up — every hiccup fixed at source, not patched in place:**
  - Stale DynamoDB state-**digest** rows from the prior teardown broke `tofu init`
    → swept; TEARDOWN.md leak-sweep gained the item.
  - **Three LLM authoring misses, each caught live:** prod `20-security` shipped
    without a `backend.tf` (layer silently applied into local state — fixed +
    `-migrate-state`; driver should preflight backend blocks); the prod
    ApplicationSet dropped dev's `hostParams` loop, then grew back a consumer
    (monitoring `InvalidImageName` — restored); and **monitoring was cut from prod
    without an explicit ask** — the human's "why?" reinstated it properly
    (`values-prod.yaml`, env-scoped prefixes). Lesson recorded: a scope cut needs a
    question, not a buried note.
  - Dev-hardcodings the prod run flushed out: `bootstrap_argocd.sh` (4 refs →
    `ENV`-parameterized), `platform.sh cluster` (inventory layer/file), `ansible.cfg`
    SSH key (→ per-env group var in the generated inventory), `kubeconfig_setup.sh`
    (env compute dir + private-IP fallback).
  - **Human directive — no operator-memory steps:** the kube-API tunnel for private
    nodes became driver-managed (`api_tunnel.sh`, self-scoping, called by every
    kubectl phase) after the LLM first offered a "run this in a second shell"
    recovery. Same posture for the deploy-key trip (bit its second run): now a hard
    gate in the `gitops` phase + symptom-first docs in BOOTSTRAP/README/RECOVERY.
  - ArgoCD operational lessons banked in RECOVERY.md: a hand-deleted Helm-hook Job
    wedges the in-flight sync (terminate-then-resync); a forced operation doesn't
    reliably honor `CreateNamespace`; `gitops()` now asserts the ApplicationSet
    exists (the emitted stream's `|| true` tail had masked a failure).
- **Design question by the human, answered honestly in ADR-0019:** a hand-applied
  ApplicationSet is *not* fully GitOps — felt three times today; the root-app fix is
  designed (include-globbed cluster-config app, `in-cluster.yaml` excluded) and
  deferred past delivery by the human's call against the clock.
- **Outcome:** prod 7/7 Synced/Healthy on private nodes, demo-app through the NLB,
  monitoring included. Docs link-swept after the human moved LEADERSHIP/TIMETABLE to
  root. Guardrails held: human drove every apply/sync, finalized every commit.

## 2026-06-14 — Refactor item 1, pass 1: carried-bug fixes (automation overhaul)

- **Used for:** Entry pass on the major-refactor item 1 (bring tooling into closer
  adherence with `notes/GUIDANCE.md`). Scope chosen by the human ("fix carried bugs
  first") from a surfaced gap list. Four offline, no-infra changes:
  1. **`operator()` comment/body mismatch fixed.** The DR phase's comment claimed an
     EBS CSI + gp3 install the body never did (and a hedge `end_function` message
     papered over it) — a masked DR failure: recovery PVCs hang Pending (GUIDANCE
     §2.6). New emit-style `gitops/bootstrap/install_ebs_csi.sh` renders the **same
     committed `ebs-csi/values.yaml`** the ApplicationSet wave 0 uses, so the
     standalone path can't drift from GitOps; `operator()` previews→confirms→pipes
     it and asserts the `gp3` class exists. RECOVERY.md Step 4 updated.
  2. **`preflight()` backend guard** — closes the very lesson the 2026-06-10 prod run
     banked ("driver should preflight backend blocks"): warns if any layer lacks
     `backend "s3"` (missing = silent LOCAL state).
  3. **`_run_phases` resume guidance** — a halted happy-path run now prints the
     stopped phase + exact resume command + phases-not-reached. Dual-mode: EXIT trap
     for direct runs (end_function exits), return-catch when sourced (no parent-shell
     trap pollution).
  4. **`generate-inventory.sh` → `generate_inventory.sh`** (snake_case rule; live
     callers updated, `notes/` history left as the record it is).
- **LLM self-caught bug:** first `_run_phases` draft used `if ! "$phase"; then rc=$?`
  — `$?` captured the negation's status, not the phase's (sourced-mode test showed
  `rc=0` for a phase that returned 3). Fixed to `"$phase"; rc=$?`. Validated both
  modes offline (bash -n + shellcheck clean).
- **Discovered + parked (item 3):** `ebs-csi/values.yaml` hardcodes `brzl-dev-k8s`;
  prod consumes it too, and the recovery path is dev-pinned end-to-end. Left faithful
  for now (fixing it here would diverge the standalone path from GitOps).
- **aroni note:** the `operator()` bug is a genuine co-firing of masked-failure
  (cand-001) × doc-rot (cand-003) — flagged in SCRATCHPAD for the parallel aroni
  session to ingest once this work is live-verified into RETROSPECTIVE.
- **Not yet verified:** offline-validated only; awaits a live `platform.sh operator`
  / `restore` run before it graduates to RETROSPECTIVE. Guardrails held — no billable
  or cluster-mutating commands run.
- **Pivot to item 3 (env realignment) — pass 1 + a methodology correction.** Audit
  showed the prod ApplicationSet's `imageParams` already swap `brzl-dev-*`→`brzl-prod-*`,
  so the `brzl-dev-*` in shared `infrastructure/*/values.yaml` is a dead (overridden)
  GitOps sentinel — but a LIVE latent bug for the two STANDALONE consumers that read
  those files directly: `install_ebs_csi.sh` and `render_recovery_manifest.sh` would
  pull prod DR images from the dev cache repos. Fixed: install_ebs_csi swaps the k8s
  prefix per `$NAME_PREFIX`; cluster-recovery.yaml + its renderer gained a third
  sentinel `__PULLTHROUGH_PREFIX__`. GitOps values left pristine. Offline-verified
  (prod + dev renders).
- **Human correction, integrated:** "env-DRY" must NOT collapse dev/prod — the parallel
  same-root trees ARE the dev→staging→prod promotion gate (prove pre-prod before the
  reputation-exposed prod). Recalibrated BACKLOG item 3 around *intentional separation
  (keep) vs accidental coupling/drift (fix)*; DRY lives in shared modules/templates,
  not in merging instances. Saved as a cross-session memory + flagged as an aroni
  cand-002 (env-coupling) refinement.

## 2026-06-15→17 — Item 3 (env realignment → model B) built + conductor/multi-account design

- **Used for:** Executing the env-layout refactor and designing the next pass, human
  steering throughout. (a) **Model B built:** all six Terraform layers migrated to a
  single-source `terraform/stack/aws/<layer>` + per-env `dev/prod.tfvars`, with the
  env carried by the **driver-composed S3 backend object key** (one bucket + CMK; no
  `backend.hcl`) and `-var-file`; intentional dev/prod differences (40-ecr toolbox,
  50-compute placement + count-gated NLB) expressed as inputs, not forks. `platform.sh`
  rewired; old `environments/{dev,prod}` trees removed (conductor kept). All offline-
  validated (6/6 `tofu validate`, fmt + shellcheck clean) — **no AWS apply yet**
  (greenfield; live test is the next session). (b) **Docs SoT restructured:** promoted
  `SPEC.md` to root, CLAUDE.md delegates standing decisions to it (SSOT, cand-004),
  fixed the drift it had bred; added ADR-0020.
- **Two human corrections, both integrated (and aronized):** (1) *instances vs source
  layout* — the promotion gate is separate instances, orthogonal to whether source is
  duplicated; my "keep the duplication" defended the wrong thing. (2) *conductor is not
  a per-env layer* — it's a temporary, per-account, single-purpose IaC distributor
  (CI-runner-like), integral to the multi-account future; I'd defaulted to folding it
  into the stack. Both are the **same error** (reading a thing's role from its current
  location) → captured as aroni Episodes B + C (inbox), a candidate "don't infer essence
  from structural placement" generalization.
- **Design settled for the next pass (SPEC §9, directional, NOT built):** per-account
  conductor; clone+pipe deploy delivery (vs S3 tree-ship + on-box monolith — squares
  GUIDANCE §1.8); ONE fine-grained PAT (refines "scope to job" = no broader than needed,
  not one-token-per-call); optional least-priv cross-account shared-services chosen at
  bootstrap for a **unified vulnerability-scanning regime**; dual-mode ECR (pull-selective
  default + push-for-hotfix via replication).
- **Guardrails held:** zero billable/cluster-mutating commands run all session — every
  change offline (validate/fmt/shellcheck/`-backend=false`). Git managed per the
  delegation (small message-honest commits; no secrets staged — verified the rendered
  ARN tfvars stay gitignored). Left a SCRATCHPAD **SESSION HANDOFF** pointing at the
  live test as the resume point.

## 2026-07-06 — Portfolio reframe (Tier 1, T1): take-home voice → platform voice

- **Context.** First session of the post-delivery *portfolio conversion* arc
  (plan: Third Lobe `Planning/10-barzel-cluster-portfolio.md`, Tier 1). Single
  task T1: make the repo read as a platform, not an assignment submission, to a
  stranger reading README top-to-bottom.
- **LLM used for:** locating every evaluator/assignment-framed passage across
  README + `docs/` (grep sweep), drafting the replacement prose, and applying the
  edits. Human picked the task, set scope, and will double-check wording.
- **Changes (5 files):** README "Preliminary note on my use of Claude" →
  **"How this was built"** (honesty + the `seed_demo_data` postcondition lesson
  kept; evaluator address dropped; single link to this log retained). De-assignment
  sweep: README `challenge brief`/`(evaluation)`, ARCHITECTURE `the assignment`/
  `original vendor's substrate`/`the brief`, BOOTSTRAP `Evaluators`. Dropped the
  README **Governance** doc-map block and the stray broken `TIMETABLE.md` inline
  link; added a **Historical** `notes/` entry + a `notes/` repo-layout row; fixed
  the `docs/` row (it wrongly claimed leadership/LLM-conduct, which live in `notes/`).
- **Human directive banked in CLAUDE.md:** with LLM-CONDUCT no longer linked from
  the README front door, the "append every session" obligation was re-anchored in
  CLAUDE.md (re-injected each session, visible to subagents) so it can't fall out
  of view post-compaction. Path corrected to `notes/LLM-CONDUCT.md`.
- **Decisions:** `notes/LEADERSHIP.md` + `notes/TIMETABLE.md` kept as unlinked
  history (not deleted) per the plan's keep-and-label recommendation. Company-name
  check (`enclaive` et al.) clean; original brief text in `notes/TASK.md` left as
  labeled history rather than rewritten.
- **Verification:** grep across README + `docs/` clean of assignment framing; all
  README `.md` links resolve. The "reads as engineering maturity" half is the
  human's judgment (deferred, correctable later).

## 2026-07-07 — Portfolio T2: secrets & history sweep → account-id leak found + history rewritten

- **Session shape:** plan adoption (the Third Lobe portfolio note folded into
  BACKLOG/SCRATCHPAD as Tier 1/Tier 2, reconciled against repo state) + the full
  T2 sweep. Human set the pivot, answered the one remediation fork; LLM ran the
  sweeps and edits.
- **LLM used for:** refreshing the expired toolbox aws-cli GPG key (AWS extended
  the same key to 2027-07-01; fetched from the AWS docs, fingerprint-verified with
  `gpg --show-keys` before overwriting the vendored file); gitleaks (8.30.1) over
  full history + added-files sweep + account-id/resource-id greps; triage; the
  `git filter-repo --replace-text` rewrite; post-rewrite verification.
- **The finding (the human's own rule paid off):** the plan said *verify
  ADR-0016's account-id-free claim, don't trust it* — and the claim failed:
  the live account id sat in three `notes/` files (pasted terminal output) in
  every commit since the initial snapshot. Ledger row 15 + an ADR-0016 amendment
  record it; the lesson is that a hygiene claim is scoped to the surfaces it
  instruments.
- **Human decision:** history rewrite (vs tree-only scrub / squash-republish) —
  chosen while the repo is still private, explicitly weighing the standing
  never-rewrite-published-history rule. LLM executed: backup bundle → filter-repo
  (id → `123456789012`, dead take-home resource ids → docs-style placeholders,
  distinctness preserved) → force-push → re-verified zero occurrences across all
  blobs; `.gitleaksignore` pins the 3 triaged false positives so the future CI
  gate (T5) runs clean.
- **Verification:** gitleaks exits 0; all-blob grep for the id: 0; placeholder
  counts match the original occurrence map (4/5/1). All commit hashes changed —
  other clones must hard-reset, noted in SCRATCHPAD.

## 2026-07-07 (later) — Memory files + working notes stripped from public history; T3 storefront

- **Human directives:** (1) remove BACKLOG/SCRATCHPAD/RETROSPECTIVE from the
  remote and its history (operator/agent working memory, not portfolio
  material); (2) likewise ALL `notes/*.md` except GUIDANCE and LLM-CONDUCT;
  keep everything locally. Human also disclosed the repo went public a few
  hours before the T2 scrub finished — accepted as reputational-only exposure
  (the GitHub-support gc option for orphaned pre-rewrite objects was noted and
  left optional).
- **LLM used for:** two further `git filter-repo --invert-paths` passes
  (backups bundled first), gitignore patterns with whitelist exceptions,
  restoring the local copies untracked, re-pinning `.gitleaksignore` after
  each rewrite (fingerprints are commit-anchored), force-pushes, and
  verification (zero tree entries for the removed paths across all commits;
  gitleaks exit 0). Public history is now 27 commits of platform work only.
- **T3 (green-lit):** description + the 8 planned topics set via `gh repo
  edit`; GraphQL schema introspection confirmed profile pinning has no API
  (manual step); the 3-sentence application blurb drafted into the planning
  note. T4 (demo script + recording) is the next Tier-1 item.

## 2026-07-07 (evening) — T3.5/R1: GUIDANCE.md polish (the standard before the enforcement)

- **Scope:** the doctrine doc itself, ahead of R2's script refactor (the vault
  note's own sequencing: polish the standard before enforcing it).
- **LLM used for:** the full editorial pass; human set the round and reviews
  the diff. Changes: (1) header/provenance updated — no longer a single-session
  personal draft; it's the published, load-bearing standard the tooling is held
  to. (2) New §1.10 "a script's claims are part of its contract" (no trailing
  `|| true` vouching for a run; phase claims must match bodies; drivers
  preflight invariants + leave a resume trail) — doctrine distilled from the
  June carried-bug fixes. (3) §1.7 generalised from account-bearing to
  env-bearing derivation (the `brzl-dev-*` standalone-path leak). (4) §2.3
  updated to model B (single-source layers, gate = separate instances,
  pointer to SPEC §3/ADR-0020). (5) New §2.9 "a claim needs an instrument"
  (today's ADR-0016 lesson: scope claims to instrumented surfaces; standing
  claims get standing CI checks). (6) Part 3 CLAUDE.md seed re-synced — it had
  drifted from Parts 1–2 (missing orchestrator-as-stream, the one-PAT nuance,
  §2.8) — and now carries an explicit §2.9-style maintenance rule naming
  itself a rendered copy. (7) Appendix extended with six new concrete moments
  (the `|| true` mask, the operator() claim/body lie, the `if ! cmd` rc-capture
  trap, the env-coupling leak, the account-id/ADR-0016 audit).
- **aroni note:** §1.10 and §2.9 are the vault's cand-001 (masked failure),
  cand-003 (doc rot), and cand-004 (SSOT) flowing INTO the standard — the
  consolidation loop feeding doctrine, which R2 will now enforce in code.
