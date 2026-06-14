# CLAUDE.md — barzel-cluster Platform

Context and rules for any Claude Code / Cowork session in this repo. The
take-home that produced this snapshot is delivered and **no longer the
governing scope** — the historical working files (`SPEC.md`, `PLAN.md`,
`TASK.md`, the run reports) live under `notes/`, tracked, as reference. The
design doc remains `docs/ARCHITECTURE.md` (+ ADR log).

## Memory files — read these first, every session

Three root files are the session-spanning memory, consumed regardless of where
in a session (or compaction cycle) you are. **Re-read them after any context
compaction.**

- **[RETROSPECTIVE.md](RETROSPECTIVE.md)** — episodic, **append-only** record
  of completed + validated + **user-verified** work, timestamped. Records are
  never modified; later entries may reference or supersede earlier ones,
  additively. Write an entry only at user-verified completion.
- **[SCRATCHPAD.md](SCRATCHPAD.md)** — working memory, user-exposed. Keep it
  current at checkpoints (task pickup, significant finding, session end);
  prune freely; it backs up your in-context state, it is not a record.
- **[BACKLOG.md](BACKLOG.md)** — the shared plan-of-record; both the user and
  the agent edit it. Pull the next task from here; park discovered work here.

Lifecycle: BACKLOG (planned) → SCRATCHPAD (in flight) → RETROSPECTIVE (done,
verified, immutable).

## aroni — the consolidation method (meta-keyword)

**"aroni"** names both the semantic-memory vault
(`~/Local/github.com/ryderdain/aroni`) **and** the method/skill that populates
it. When the user invokes "aroni" at a meta level, engage that machinery:
- spec + invariants → `daemon/CONSOLIDATION_DAEMON.md`
- the repeated procedure → **`daemon/ARONI_METHOD.md`** (run this each cycle)
- tooling → `daemon/*.py` (ingest / bundler / scheduler / vault_check)

Two standing rules the method turns on:
1. **Surface candidates in the vault, never in chat alone.** A drafted+gated
   candidate is staged in `aroni/_candidates/` (note + `.gate.md`) so the
   arbiter reads it in Obsidian before ruling.
2. **Rationale is conditional.** Required on reject/revise and non-obvious
   accepts; **optional on a face-valid accept** — a later pass refines the
   belief, and that deferral is the method working, not a gap.

## What this repo is
A GitOps-driven infrastructure platform for a Lead Infrastructure Engineer take-home (a confidential-computing vendor): Terraform provisions AWS infra, Ansible bootstraps k3s, ArgoCD syncs the cluster, CloudNativePG manages a stateful Postgres, and a demo REST app reads/writes it. Deliverable is a reproducible repo + docs + leadership answers.

## Repo layout
- `terraform/` — modules + `environments/{dev,prod}` (layered, per Lee Briggs IaC structure; read from <https://leebriggs.co.uk/blog/2023/08/17/structuring-iac>).
- `ansible/` — `roles/{base,kubernetes,security}` + `playbooks/`
- `gitops/` — `clusters/{dev,prod}`, `infrastructure/`, `applications/`, `operators/postgres/`
- `apps/demo-app/` — REST API + Dockerfile
- `docs/` — `ARCHITECTURE.md` (delivery-facing design + ADR log), `SECRETS.md` (credential/key/secret inventory), lifecycle, security, leadership answers
- `docs/` runbooks — `BOOTSTRAP.md`, `UPGRADE.md`, `RECOVERY.md`, `TEARDOWN.md` (living operator runbooks)
- `terraform/identity/` — trust anchor: GitHub OIDC provider + scoped `tofu-plan`/`tofu-apply` roles (admin-run once, after `bootstrap/`)
- `containers/` — `toolbox/` (arm64 tofu/ansible/kubectl/helm image) + `bootstrap-vm/` (cloud-init) *(planned, SPEC §4.2)*
- `SPEC.md` — end-design target/scope (internal) · `docs/ARCHITECTURE.md` — delivery-facing design + ADRs · `PLAN.md` — execution checklist · `LLM-CONDUCT.md` — log of LLM use

## Living docs — keep in sync (don't lose across compaction)
These evolve together every iteration; when a design/decision changes, update **all** of the affected set, not just one:
- **`SPEC.md`** is the internal working scratchpad / source of truth for scope, differentiators (§4: SSO/OIDC identity; toolbox/bootstrap containers), and resolved decisions (§7). **New decisions land here first** (SPEC iterates).
- **`docs/ARCHITECTURE.md`** is the **delivery-facing** design doc: the curated distillation of SPEC + a running ADR log (ARCHITECTURE curates). When a decision resolves in SPEC, promote it here — add/update the matching **ADR** and the affected prose. This is what a reviewer reads; keep its links valid (no links to gitignored `SPEC.md`/`PLAN.md`/`TASK.md`).
- **Runbooks** (`docs/BOOTSTRAP|UPGRADE|RECOVERY|TEARDOWN.md`) are the operator-facing realization. A change to identity, KMS, backups, or the toolbox must be reflected in the relevant runbook(s):
  - identity/OIDC + KMS + secrets-hygiene → `BOOTSTRAP.md` (phases 0–2) + `TEARDOWN.md` (KMS/state sweep)
  - operator/CI toolbox + session-timeout-safe long ops → `UPGRADE.md` (+ `BOOTSTRAP.md` long phases)
  - CNPG backup/restore + instance-profile auth + state recovery → `RECOVERY.md`
- **`docs/SECRETS.md`** is the credential/key/secret inventory (delivery-facing). Any change that adds, moves, or retires a credential, KMS key, Secrets-Manager/SSM entry, in-cluster Secret, or gitignored secret-bearing file must update the matching `SECRETS.md` row (+ the ADR if the decision is new).
- **`PLAN.md`** schedules the work; **`LLM-CONDUCT.md`** logs LLM use each session.
- Runbooks set: `docs/{BOOTSTRAP,ACCESS,UPGRADE,RECOVERY,TEARDOWN}.md`. Scaling and backups are **automated** (HPA / CNPG `.spec.instances` / Terraform node count; CNPG→S3 continuous+scheduled) and described in the top-level `README.md` — no separate SCALING runbook.

## Documentation convention — README is the front door
- The **top-level `README.md` is the primary documentation file.** It orients the reader (architecture-at-a-glance, repo layout, reproduce steps, scaling/backups automation) and points to the expanded delivery docs (`docs/ARCHITECTURE.md` + the operator runbooks `docs/*.md`). It must not link to gitignored working files (`SPEC.md`, `PLAN.md`, `TASK.md`) — those won't exist in a fresh clone.
- **No per-directory/leaf `README.md` files** — they add cognitive noise and drift. Describe each area in the top-level README and detail it in `docs/ARCHITECTURE.md` or the relevant runbook. When adding a new area, add a line to the README's documentation map, don't create a nested README.

## Standing technical decisions (do not silently change)
- **Kubernetes:** k3s, HA (3 servers, embedded etcd). Not kubeadm/Talos.
- **Terraform:** modular, reusable, strict dev/prod separation; remote state in S3 + DynamoDB lock.
- **Registry:** AWS ECR for images AND OCI Helm charts, with pull-through cache (Docker Hub, registry.k8s.io). Document Harbor as the production recommendation.
- **Storage:** EBS CSI driver + gp3 default StorageClass for PVCs. `local-path` only as an explicit, documented fallback.
- **Backups:** CloudNativePG → S3 via Barman Cloud. Authenticate using the EC2 instance profile — do NOT create a second IAM user.
- **GitOps:** ArgoCD app-of-apps; sync waves so operators land before applications.
- **CI:** keep all pipeline/runner definitions generic and CI-system agnostic (must work on GitHub Actions or GitLab CI).
- **State bucket name — DERIVED, never an env var.** The S3 state bucket is `brzl-demo-tfstate-<account_id>`. The layer's own `backend` block can't use a data source, so `../backend.hcl` (gitignored, copied from `.example` once at bootstrap) carries the literal. But the `terraform_remote_state` **data sources** that read lower layers now derive the bucket via `data.aws_caller_identity.current.account_id` in each `remote_state.tf` — **no `TF_VAR_state_bucket`**. Do NOT reintroduce a per-run env var for account-bearing values: if I can drop it between runs (I did — `NoSuchBucket` on a destroy), so can any operator. Derive account-bearing names at runtime from the caller, or persist them in a gitignored file tofu auto-loads — never lean on the operator's shell memory.
- **Operations run from the toolbox, not the laptop.** From pre-flight onward, the standard execution locus for infra/cluster operations (bootstrap, recovery, deploy, teardown) is the **operator toolbox** — the pinned `containers/toolbox/` image — run either **in-cluster** (`gitops/tools/toolbox_shell.sh`) once the cluster exists, or on a **one-off disposable EC2 "conductor"** (arm64 `t4g.*`, Graviton — the toolbox image is `linux/arm64`) reached via **SSM Session Manager** (no inbound SSH). Three goals this serves: (1) **identical toolchain across all operators** — no version drift between bootstrap/recovery/deploy; errors are reproducible/traceable; (2) **operator entry is IAM-gateable** — authorization constrained to the toolbox/SSM, not scattered laptops; (3) **all activity is audited** — toolbox operations + the triggering identity (SSM/IAM) are logged. Operator scripts must therefore run **both** with `AWS_PROFILE=<assumed-role>` (laptop) **and** with no profile (instance-role creds on the conductor) — don't hard-require `AWS_PROFILE`. The conductor is built as a **self-contained `00-conductor` layer** (own VPC/subnet/IGW, inline IAM, fully deploy/destroyable without touching any other layer — DRY deliberately relaxed there). **Execution locus splits by environment:** the **AWS environments (`dev`, `prod`) run from the conductor** via `gitops/tools/platform.sh` (`ENV=dev|prod`, the AWS orchestrator — it *rejects* `local`); the **laptop is only for (a) the admin trust-anchor bootstrap** (`terraform/bootstrap` + `terraform/identity`, run once as the admin user) **and launching the conductor** (`platform.sh conductor`), **and (b) the entire local-dev (k3d) environment**, which is laptop-native via `gitops/clusters/local/k3d_up.sh` (no AWS, no conductor). So: AWS ops → conductor; local-dev + the one-time conductor launch → laptop. (local-dev itself was above-and-beyond `TASK.md` scope — kept as the portability story, not a required target.)

## Bash-specific design decisions
- Only draft Bash scripts using the guidelines set out in <https://mywiki.wooledge.org/BashPitfalls>.
- Only ever use `set -euo pipefail` if you can explain what it does — read the linked BashPitfalls (esp. <https://mywiki.wooledge.org/BashFAQ/105> on `set -e`'s unreliability). Do not paste it reflexively; prefer explicit return-code checks.
- **Mutating/action** scripts (deploy, build, teardown) should print the commands they would run to /dev/stdout and execute by piping into a shell (`bash foo.sh | bash`), so the actions are previewable before they run. **Read-only check/generator** scripts instead run their queries directly and emit a report (or data) to stdout with a meaningful exit code — e.g. `ansible/inventory/generate-inventory.sh`, `gitops/tools/*_status.sh`. (When a mutating emit-commands script is piped into a downstream consumer such as a Terraform `local-exec`, wrap it `set -o pipefail; bash gen.sh | bash` so a generator failure isn't masked, and emit the commands `&&`-chained so the run fails fast.)
- Prefer bashisms over additional tools for string modifications.
- Prefer mandating a minimum Bash version and enforcing this with a general check over backwards-compatibility.
- **Naming: snake_case** for script filenames AND for variable/identifier names across all code — unless a stronger, more widely recognised convention governs the language (e.g. Go's gofmt-enforced MixedCaps; Kubernetes manifest keys stay camelCase). Terraform and Ansible identifiers are already snake_case. (So `foo_bar.sh`, not `foo-bar.sh`.)
- **Sourceable `main()` pattern** (per `ryderdain/bash/tests/destroy-tf-modules.sh`): structure action scripts so they can be **run directly OR `source`d** by an orchestrator. Detect with `(return 0 2>/dev/null) && is_sourced=true || is_sourced=false`; put logic in named functions; finish each with a shared `end_function $? 'msg'` that **logs and then `return`s when sourced but `exit`s when run directly** (so a sourced caller isn't killed by a callee's failure); end the file with a CLI-dispatch block that runs the default pipeline (or `"$@"` to call a named function) only `if [[ "$is_sourced" = false ]]`. This composes with — does not replace — the emit-commands convention: an emit-style action's function still *prints* the commands (the orchestrator pipes them, `bash x.sh | bash`); a generator's function prints data. The point is a clear, consistent calling surface so an orchestration script can sequence complex actions legibly for junior operators.
- Read from and make use of ryderdain/bash as warranted.

## Design personalizations
- Prioritize scaffolding and infrastructure with Terraform, delegate configuration of Kubernetes to ArgoCD, and employing Ansible primarily for application bootstrapping and configuration.
- Read from github repository ryderdain/tw-project to understand personal style and approach.

## GUARDRAILS — confirm in chat before running any of these
Treat AWS as billable. NEVER run the following without my explicit, in-chat confirmation:
- `terraform apply` or `terraform destroy`
- `ansible-playbook` against real hosts
- `kubectl delete` / `helm uninstall`
- any mutating `aws` CLI command
Always print the exact command and what it will create/change/cost first. Prefer Plan mode for infra changes. Use a scoped AWS profile.

**Always ask, never assume.** In this project, default to asking before proceeding with any operation, gate, or layer — never auto-advance on the assumption that prior approval carries forward. When the choice is "ask vs. just proceed," always ask. Per-step in multi-step sequences (e.g. the dev infra layers), ask before each one.

**Saved-plan apply workflow.** For every billable/mutating OpenTofu change: `tofu plan -out=<file>`, surface it for review, then apply that exact file (`tofu apply "<file>"`). Never `tofu apply -auto-approve` (re-plans fresh; can drift from what was reviewed). Saved plan files are gitignored (`*tfplan*`) — they can embed resolved variable values.

### Cost-leak watch (for teardown verification)
`terraform destroy` does not catch everything. After teardown, remind me to manually check: NAT gateway, Elastic IPs, EBS volumes created behind PVCs, LoadBalancer Services, and the state bucket/lock table. Intentionally-left artifacts (ECR images, S3 backups) must be listed explicitly.

## Workflow
- Confirm access rights and permissions before testing, request from user as needed.
- Work one PLAN.md block at a time (commits map to blocks — supports the GitOps/release story).
- **Git division of labor (delegated 2026-06-12):** the working tree of this repo and the vault (`aroni`) is **Claude's to manage** — staging, commits, and pushes, without per-commit confirmation. Standing obligations: surface what was committed in chat, keep commits small and message-honest, flag any secrets/leak concern BEFORE pushing, and never rewrite published history. The infra guardrails above are unaffected — billable/mutating cloud operations still gate on explicit confirmation.
- Use git commits as rollback checkpoints.
- Show diffs and wait for approval; do not auto-accept infra changes.
- Keep secrets out of git. No credentials in manifests, tfvars, or commits.

## LLM-conduct logging (challenge requirement)
At the end of each working session, append a short entry to `LLM-CONDUCT.md`: date, what the LLM was used for, and anything notable. The challenge requires documenting LLM use.
