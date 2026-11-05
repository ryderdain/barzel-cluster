# CLAUDE.md — barzel-cluster Platform

Context and rules for any Claude Code / Cowork session in this repo. The
take-home that produced this snapshot is delivered and **no longer the
governing scope**; ongoing work is the refactor in `BACKLOG.md`.

**Design directives live in [`SPEC.md`](SPEC.md) (root) — the design source of
truth.** Standing technical decisions, the environment/state model, and new
design decisions land there first (then promote to an ADR in
`docs/adr/`). This file does **not** restate them — it carries the
*operational* contract (memory protocol, guardrails, workflow, git, aroni) and
points at SPEC for the *what/why* of the design. The take-home working files
(`notes/PLAN-HISTORICAL.md`, `notes/TASK.md`, the run reports, GUIDANCE, the
LLM-conduct log) live under `notes/`, **local-only and gitignored — never
published** (they belong to the private project barzel derived from); the
delivery-facing design doc is `docs/ARCHITECTURE.md`
(+ the ADRs in `docs/adr/`, one file each, indexed from ARCHITECTURE).

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
it. The vault is **self-contained and shared** — barzel is just one episode
source (its `RETROSPECTIVE.md`). When the user invokes "aroni" at a meta level,
engage that machinery (it lives in the vault repo):

- spec + invariants → `../aroni/SPEC.md`
- the repeated procedure → **`../aroni/METHOD.md`** (run this each cycle)
- tooling → `../aroni/tools/` (ingest / bundler / scheduler / vault_check /
  init_project)
- onboarding another repo/domain → `../aroni/ADOPTING.md`

Two standing rules the method turns on:

1. **Surface candidates in the vault, never in chat alone.** A drafted+gated
   candidate is staged in `aroni/_candidates/` (note + `.gate.md`) so the
   arbiter reads it in Obsidian before ruling.
2. **Rationale is conditional.** Required on reject/revise and non-obvious
   accepts; **optional on a face-valid accept** — a later pass refines the
   belief, and that deferral is the method working, not a gap.

## What this repo is

A **platform**: a general, secured Kubernetes cluster that runs on several
substrates (k3d on a laptop, AWS, later GCP or DigitalOcean) with as few changes
as possible, as the backbone of a CI/CD chain. It does not depend on any
workload; an example app shows stateless and stateful workloads. Local is the
first environment: a driver (kiesei) runs phases through run sheets, services
that a cloud keeps outside the cluster (registry, secret store, log data) run
outside it locally too, and Argo CD syncs the cluster. It began as a take-home
for a confidential-computing company (AWS, k3s, CNPG); confidential computing is
now a guide, not the goal (SPEC §1).

Local (k3d) is the only live environment at this time (ADR-0024). The AWS
path (`gitops/tools/platform.sh`, `terraform/environments/dev/00-conductor`)
is frozen until the substrate-adapters pass (BACKLOG item 10). Do not extend
it. The project terms (kiesei, driver, conductor, locus, phase, run sheet,
substrate adapter, environment definition) are in
[`GLOSSARY.md`](GLOSSARY.md). Use those words. A new or changed term goes
into GLOSSARY first.

## Repo layout

- `driver/`: the local-first operations driver (ADR-0022).
  - `BRZL_ENV=<env> driver.sh <mode> <verb>` is an emit script. It prints
    a run sheet and runs nothing. The modes are `cluster`, `break-glass`
    and `audit`. The verbs are in its usage line (ADR-0038). The bootstrap
    phases are
    `phases/{10-substrate,20-images,25-bootstrap,30-gitops,40-workloads}.sh`.
  - `kiesei.sh` runs the emitted stream in the `kiesei:local` image.
    `kiesei.sh shell` opens a signed-in shell.
  - `conductor.sh` sends a conductor phase to the in-cluster pod. The driver
    calls it. Do not run it by hand.
  - Adapters: `substrates/k3d.sh`, `secret-stores/openbao.sh`. Modes:
    `modes/break-glass.sh`, `modes/audit.sh`. GitHub access setup:
    `access/github.sh`.
  - `lib/runlib.sh` and `lib/error.sh` are vendored from `ryderdain/bash`
    and pinned in `lib/UPSTREAM`. Change them upstream first, then re-vendor.
  - `tests/driver-cases.sh` tests the driver mechanics with no cluster.
- `env/local.env`: the environment definition. It is plain `NAME=value`
  with `BRZL_*` keys and no secrets. An exported value overrides it for one
  run.
- `var/` (gitignored): run sheets and run outputs in `var/run/<env>/`
  (`current` is a symlink to the latest run), the local log stores, the
  local secret-store keys, and the GitHub App material. It contains secrets.
  Never commit it, and never print its key or token files.
- `gitops/`: `platform/applicationset.yaml` (the single ApplicationSet),
  `clusters/{local,dev,prod}`, `infrastructure/` (one directory for each
  platform service), `operators/postgres/`. The `bootstrap/` and `tools/`
  directories are AWS-era and frozen.
- `terraform/`: `bootstrap/` (state bucket and CMK), `identity/` (GitHub
  OIDC and the `tofu-plan`/`tofu-apply` roles), `modules/`, and
  `stack/aws/<layer>` with committed `dev.tfvars` and `prod.tfvars` (layered
  per Lee Briggs, <https://leebriggs.co.uk/blog/2023/08/17/structuring-iac>).
- `ansible/`: `roles/{base,kubernetes,security}` and `playbooks/` (AWS
  path).
- `containers/`: `kiesei/` (the toolbox image, built locally as
  `kiesei:local`) and `bootstrap-vm/` (cloud-init template).
- `docs/`: `ARCHITECTURE.md` (the ADR index), `adr/NNNN-slug.md` (get the
  next number from the directory), `SECRETS.md`, `SECURITY.md`, the runbooks,
  and `guide/`.
- The example app is a separate repo, `../chofesh` (ADR-0034). It is not in
  this tree.

## Commands

The driver prints. The pipe runs. A pipe into `kiesei.sh` or `bash` is the
approval. Thus a piped `cluster bootstrap`, `cluster teardown`, `break-glass
open`, `break-glass apply`, `break-glass close` or `audit bootstrap` changes
the cluster or the machine. Ask the user before each one, per the "always
ask" rule below. A teardown runs nothing until `sed 's/^## ⚠ ## //'` is in
the pipe. For the full set (break-glass, audit, GitHub access setup), read
[`docs/LOCAL.md`](docs/LOCAL.md).

```bash
docker build -t kiesei:local containers/kiesei            # build the toolbox image
export BRZL_ENV=local                                     # the environment (the default, until BACKLOG 38)
bash driver/driver.sh cluster bootstrap                   # read the unfinished phases (safe)
bash driver/driver.sh cluster bootstrap | bash driver/kiesei.sh   # operate them (mutating)
bash driver/driver.sh cluster status                      # read-only
bash driver/driver.sh cluster teardown | sed 's/^## ⚠ ## //' | bash driver/kiesei.sh   # remove the cluster
bash driver/tests/driver-cases.sh                         # driver tests, no cluster
bash driver/lib/upstream-check.sh                         # vendored-lib pin check
shellcheck -x <file.sh>
npx --no-install markdownlint-cli2 <file.md>
```

The repo has no CI, Makefile, or pre-commit configuration. The checks above
are all the checks.

## Living docs — keep in sync (don't lose across compaction)

These evolve together every iteration; when a design/decision changes, update
**all** of the affected set, not just one:

- **`SPEC.md`** (root, tracked) is the internal **design source of truth**:
  standing technical decisions (§3 — the one home), scope, differentiators (§4),
  resolved decisions (§7). **New design decisions land here first** (SPEC
  iterates), then promote to ARCHITECTURE.
- **`docs/ARCHITECTURE.md`** is the **delivery-facing** design doc: the curated
  distillation of SPEC + the ADR index (ARCHITECTURE curates). When a decision
  resolves in SPEC, promote it here — add a new **ADR** file in `docs/adr/`
  (next number; mark any superseded ADR's Status, never delete it), add its
  index row, and update the affected prose. This is what a reviewer reads; keep
  its links valid (it's fine to link `SPEC.md` now that it's root+tracked; don't
  link the `notes/` take-home working files from the delivery-facing docs —
  they're reference).
- **Runbooks** (`docs/BOOTSTRAP|UPGRADE|RECOVERY|TEARDOWN.md`) are the
  operator-facing realization. A change to identity, KMS, backups, or the kiesei
  must be reflected in the relevant runbook(s):
  - identity/OIDC + KMS + secrets-hygiene → `BOOTSTRAP.md` (phases 0–2) +
    `TEARDOWN.md` (KMS/state sweep)
  - operator/CI kiesei + session-timeout-safe long ops → `UPGRADE.md` (+
    `BOOTSTRAP.md` long phases)
  - CNPG backup/restore + instance-profile auth + state recovery → `RECOVERY.md`
  - a driver, phase, mode, or `env/` change → `LOCAL.md` (+ `INSTALL.md` for
    prerequisites, `BREAK-GLASS.md` for hold/release)
- **`docs/SECRETS.md`** is the credential/key/secret inventory
  (delivery-facing). Any change that adds, moves, or retires a credential, KMS
  key, Secrets-Manager/SSM entry, in-cluster Secret, or gitignored
  secret-bearing file must update the matching `SECRETS.md` row (+ the ADR if
  the decision is new).
- **`BACKLOG.md`** is the live plan-of-record (schedules the work).
- **`notes/LLM-CONDUCT.md`** (local-only) logs LLM use each session.
- **`GLOSSARY.md`** holds the project terms. A new or renamed term lands there.
- Runbooks set:
  `docs/{BOOTSTRAP,ACCESS,UPGRADE,RECOVERY,BREAK-GLASS,TEARDOWN,INSTALL,LOCAL}.md`,
  plus the topic guides in `docs/guide/`. Scaling and backups are **automated**
  (HPA / CNPG `.spec.instances` / Terraform node count; CNPG→S3
  continuous+scheduled) and described in the top-level `README.md` — no separate
  SCALING runbook.

## Documentation convention — README is the front door

- The **top-level `README.md` is the primary documentation file.** It orients
  the reader (architecture-at-a-glance, repo layout, reproduce steps,
  scaling/backups automation) and points to the expanded **delivery-facing**
  docs (`docs/ARCHITECTURE.md` + the operator runbooks `docs/*.md`). `SPEC.md`
  is the *internal* design SoT that ARCHITECTURE curates from — the README
  front-doors ARCHITECTURE, not SPEC; and it doesn't link the `notes/` take-home
  working files (reference, not part of a fresh clone's front door).
- **No per-directory/leaf `README.md` files** — they add cognitive noise and
  drift. Describe each area in the top-level README and detail it in
  `docs/ARCHITECTURE.md` or the relevant runbook. When adding a new area, add a
  line to the README's documentation map, don't create a nested README.

## Standing technical decisions → [`SPEC.md`](SPEC.md) §3 (one home)

The standing technical decisions — Kubernetes, compute, **Terraform layering +
the environment/state model** (single-source `terraform/stack/aws/<layer>` +
per-env tfvars; one state bucket + CMK, env split by S3 object key, backend
composed by the driver), registry, storage, backups, GitOps (single
ApplicationSet), CI-agnostic, node access (SSM),
**operations-run-from-the-kiesei**
(dual-locus scripts; AWS envs from the conductor, laptop only for the admin
bootstrap + conductor launch + local-dev), encryption, secrets/account-bearing
values (derived, never an env var to remember), runbooks — **live in
[`SPEC.md`](SPEC.md) §3**. Do not restate them here; do not silently change
them;
land any new design decision in SPEC first. (The saved-plan workflow and
ask-before-billable rule are *also* hard guardrails below — they bind
operationally
every session, so they stay in this file too.)

## Bash — the doctrine lives in `ryderdain/bash`

All Bash rules come from **`ryderdain/bash`** (sibling checkout `../bash`).
Before writing, editing, or reviewing any `.sh` file here — including as a
subagent — load the `bash-doctrine` and `bash-ops` skills; without the Skill
tool, Read them directly: `../bash/skills/bash-doctrine/SKILL.md` and
`../bash/skills/bash-ops/SKILL.md` (same files as `~/.claude/skills/bash-*`).
The reasoning is in `../bash/doctrine/STYLE.md` (§1.2 emitted groups, §1.11
the driver, §1.12 environment definitions); helpers in
`../bash/includes/runlib.sh`. This file does not
restate the rules, so it cannot drift from them. A rule this repo needs that
the doctrine lacks goes into `ryderdain/bash` first, then gets applied here.

## Design personalizations

- Prioritize scaffolding and infrastructure with Terraform, delegate
  configuration of Kubernetes to ArgoCD, and employing Ansible primarily for
  application bootstrapping and configuration.
- Read from github repository ryderdain/tw-project to understand personal style
  and approach.

## GUARDRAILS — confirm in chat before running any of these

Treat AWS as billable. NEVER run the following without my explicit, in-chat
confirmation:

- `terraform apply` or `terraform destroy`
- `ansible-playbook` against real hosts
- `kubectl delete` / `helm uninstall`
- any mutating `aws` CLI command
Always print the exact command and what it will create/change/cost first. Prefer
Plan mode for infra changes. Use a scoped AWS profile.

**Always ask, never assume.** In this project, default to asking before
proceeding with any operation, gate, or layer — never auto-advance on the
assumption that prior approval carries forward. When the choice is "ask vs. just
proceed," always ask. Per-step in multi-step sequences (e.g. the dev infra
layers), ask before each one.

**Saved-plan apply workflow.** For every billable/mutating OpenTofu change:
`tofu plan -out=<file>`, surface it for review, then apply that exact file
(`tofu apply "<file>"`). Never `tofu apply -auto-approve` (re-plans fresh; can
drift from what was reviewed). Saved plan files are gitignored (`*tfplan*`) —
they can embed resolved variable values.

### Cost-leak watch (for teardown verification)

`terraform destroy` does not catch everything. After teardown, remind me to
manually check: NAT gateway, Elastic IPs, EBS volumes created behind PVCs,
LoadBalancer Services, and the state bucket/lock table. Intentionally-left
artifacts (ECR images, S3 backups) must be listed explicitly.

## Workflow

- Confirm access rights and permissions before testing, request from user as
  needed.
- Work one `BACKLOG.md` item/pass at a time (commits map to passes — supports
  the GitOps/release story).
- **Git division of labor (delegated 2026-06-12):** the working tree of this
  repo and the vault (`aroni`) is **Claude's to manage** — staging, commits, and
  pushes, without per-commit confirmation. Standing obligations: surface what
  was committed in chat, keep commits small and message-honest, flag any
  secrets/leak concern BEFORE pushing, and never rewrite published history. The
  infra guardrails above are unaffected — billable/mutating cloud operations
  still gate on explicit confirmation.
- Use git commits as rollback checkpoints.
- Show diffs and wait for approval; do not auto-accept infra changes.
- Keep secrets out of git. No credentials in manifests, tfvars, or commits.

## LLM-conduct logging (standing obligation — do not let this lapse)

At the end of each working session, append a short entry to
[`notes/LLM-CONDUCT.md`](notes/LLM-CONDUCT.md): date, what the LLM was used for,
and anything notable (decisions surfaced, output corrected/overridden, what was
done by hand). This is kept deliberately as an engineering-hygiene record of
who-said-what in development — the calibrated self-assessment is a strength, not
a compliance artifact. **This obligation is anchored here in CLAUDE.md on
purpose:** the README only *references* the log descriptively (as history) — no
front-door doc tells anyone to keep appending to it. That standing instruction
lives here alone, re-injected every session and visible to subagents. Any
session
or subagent doing real work updates it; do not skip it because it isn't surfaced
elsewhere.
