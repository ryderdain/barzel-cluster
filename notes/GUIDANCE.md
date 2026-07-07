---
title: Production Bash & Infrastructure Patterns — Doctrine Seed
created: 2026-06-08
source: brzl-demo build + DR drill (2026-06); extended by the post-delivery refactor arc (2026-06/07)
purpose:
  - The standard this repo's tooling is held to (and refactored against)
  - Seed a publishable, opinionated guide to authoring Bash for production infrastructure in teams (ryderdain/bash STYLE.md)
  - Seed a pre-staged CLAUDE.md for future projects
status: living standard — published in-repo; enforcement via the refactor arc + CI checks
tags:
  - bash
  - infrastructure
  - terraform
  - gitops
  - doctrine
aliases:
  - "202606081744"
  - Production Bash & Infra Patterns — Doctrine Seed
---

# Production Bash & Infrastructure Patterns — Doctrine Seed

> First distilled from an intensive session standing up (and tearing down) a GitOps AWS platform — Terraform → Ansible → ArgoCD → CloudNativePG — and proving a full disaster-recovery restore driven from a disposable "conductor" box; since extended by the post-delivery refactor arc (each addition traceable to a concrete failure — see the Appendix). Three uses: (1) **the standard this repo's own tooling is held to**; (2) the spine of a publishable opinionated guide to **Bash in production infra for teams**; (3) a pre-staged **`CLAUDE.md`** for future projects (see Part 3).

The throughline of everything below: **the human operator's memory and keyboard are the least reliable part of the system.** Every pattern here moves state, secrets, and sequencing *out* of the operator's head and *into* the tooling — previewable, derivable, auditable, and identical across people.

---

## Part 1 — Bash: opinionated patterns for production infrastructure

### 1.1 Foundations (non-negotiable)

- **Author against the failure modes, not the happy path.** Draft against [BashPitfalls](https://mywiki.wooledge.org/BashPitfalls); assume word-splitting, unset vars, and spaces-in-paths until proven otherwise.
- **Never cargo-cult `set -euo pipefail`.** Only use a flag you can *explain*. `set -e` is famously unreliable ([BashFAQ/105](https://mywiki.wooledge.org/BashFAQ/105)); prefer **explicit return-code checks** on the commands whose failure actually matters. `set -o pipefail` alone is fine *when you can say why* (a piped generator's failure must not be masked).
- **Bashisms over extra tools** for string work — parameter expansion, not a `sed` subprocess, when a bashism does it.
- **Mandate a minimum Bash version and enforce it** with a guard at the top (`(( BASH_VERSINFO[0] < 4 )) && exit`), rather than writing for the lowest common denominator.
- **`snake_case` everywhere** — filenames *and* identifiers — unless a stronger, language-native convention governs (Go's gofmt MixedCaps; Kubernetes manifest keys stay camelCase). So `foo_bar.sh`, never `foo-bar.sh`.

### 1.2 The two script archetypes

Every script is one of two kinds, and the kind dictates its shape:

1. **Mutating / action scripts** (deploy, build, teardown) **emit the commands they would run to stdout** and are executed by piping into a shell:
   ```sh
   bash deploy.sh        # PREVIEW — read exactly what will run
   bash deploy.sh | bash # RUN
   ```
   The actions are reviewable *before* they run. Emit them **`&&`-chained** so the run fails fast. When a generator is piped into a downstream consumer (a Terraform `local-exec`, an orchestrator), wrap it `set -o pipefail; bash gen.sh | bash` so a generator failure isn't swallowed.

2. **Read-only check / generator scripts** run their queries **directly** and emit a report (or data) to stdout with a **meaningful exit code**. No preview ceremony — they don't change anything.

This split is the spine. It makes "what will this do?" answerable without a sandbox, and it makes secrets-safe previews possible (next).

### 1.3 The artifact carries structure, not secrets

The reviewable/transmittable thing an emit script produces carries **command structure and *references* — never resolved secret values.** A secret is materialised only by the **execution context**, from **its own trusted source**: an environment variable when the execution locus is your shell; a secret store (Secrets Manager, Vault) when the locus is a remote toolbox. That is the deep rule. "A dry run is safe to paste into a ticket" is just one pleasant consequence of it, not the point.

- **Reference secrets by name; let the executing shell resolve them.** The printed command contains `"$GHCR_TOKEN"`; only the shell that ultimately runs it expands the value, from *that* shell's environment. (This is *why* §1.8's remote execution wants the secret on the toolbox, not the laptop.)
- **When a tool must be *handed* a credential** (e.g. `git` over HTTPS), use **`GIT_ASKPASS`** or an equivalent so the token never lands in `argv` (visible to `ps`), in `.git/config`, or in output. Scrub remote URLs after.
- **Inspect secrets without revealing them.** A "secret peek" helper prints a key's **byte-length and charset class** (hex / base64-ish / empty), never the value — enough to catch the two classic bugs (an empty cookie secret; a base64 `+/=` secret that breaks `client_secret_basic`) without leaking anything.

### 1.4 The sourceable `main()` pattern (the team multiplier)

Structure action scripts so they can be **run directly OR `source`d** by an orchestrator. This is what lets one legible top-level driver sequence many complex actions for junior operators — without copy-pasting logic or losing the per-script preview guarantees.

The contract:

1. **Detect sourced-ness in the script's own frame, before anything else:**
   ```sh
   (return 0 2>/dev/null) && is_sourced=true || is_sourced=false
   ```
2. Put all work in **named functions**.
3. Finish each function with a shared **`end_function "$?" 'message'`** that logs the outcome and then **`return`s when sourced but `exit`s when run directly** — so a sourcing orchestrator survives a callee's failure and decides what to do, while a standalone run still fails hard.
4. End the file with a **CLI-dispatch block that runs only when not sourced:**
   ```sh
   if [[ "$is_sourced" == false ]]; then
     if (( $# )); then "$@"; else default_action; fi
   fi
   ```

This **composes with** the emit-commands convention rather than replacing it: an emit-style function still *prints* commands (the orchestrator pipes them); a generator function prints data. A small shared harness (`end_function`, `require_tools`, a creds note) can live in one sourced lib so the boilerplate isn't duplicated.

> Reference implementation in my own toolbox: `ryderdain/bash/tests/destroy-tf-modules.sh`.

### 1.5 Automation completeness — stdout is canonical, the file is an argument

If a script *produces* a value the next step *needs*, it should **put it where it belongs**, not print it for the operator to paste back. Paste-back steps are where reproducibility quietly dies.

But "write it to a file" and "render it to stdout for a pipe" should **not** be two different script shapes. Unify them with one convention for any script where *producing content is the point* (a rendered manifest, a resolved `tfvars` line, a rewritten kubeconfig):

- **Default to stdout.** With no file argument, emit the content to stdout — so it pipes directly (`bash render.sh | kubectl apply -f -`), through `tee`, or into any logging utility.
- **Accept a target path as an argument.** When one is given — *and only then* — the script also writes the content to that file (backing up an existing target first).
- **Announce the target on stderr**, never stdout (`wrote → <path>`), so the human sees where it went without polluting the piped payload.
- **Always return the content on stdout**, whether or not a file was written — so behavior is identical either way and a retained copy is a *side effect*, not a mode switch.

So the secret-creator, by default, prints the `tfvars` line(s) to stdout; pointed at the `tfvars` path it *also* writes them there (backup first), echoes the path to stderr, and still prints them. Same shape as the manifest renderer; same shape as the kubeconfig writer. One convention — composable with pipes, `tee`, and previews; no exceptions.

### 1.6 Dual-locus credentials — laptop *and* toolbox

Scripts must run unchanged in **both** credential contexts:

- a **laptop**, where AWS access comes from an assumed-role **profile** (`AWS_PROFILE=…`); and
- a **toolbox / instance**, where access comes from the **instance role** and there is **no `AWS_PROFILE`**.

So: **never hard-require `AWS_PROFILE`.** Let `aws` pick up ambient/instance-role creds; surface which is in use for the operator's benefit, but don't gate on it. (Watch the `set -u` interaction: `${AWS_PROFILE:-}` guards, and remember `sudo`/Ansible may strip the env — re-inject where a tunnel/ProxyCommand needs it.)

### 1.7 Derive account- and environment-bearing values — never lean on shell memory or a literal copy

Anything that embeds an account id (state-bucket name, registry host, role ARN) is **derived at runtime from the caller** (`aws sts get-caller-identity`) or **persisted in a gitignored file the tool auto-loads** — never carried in a per-run environment variable the operator has to remember. *If I can drop it between runs, so can any operator* (I did, once — `NoSuchBucket` on a destroy). This is a reproducibility and a correctness rule, not just hygiene.

The same rule generalises to **environment-bearing values**. Shared code that any environment consumes must **derive** env-flavored values (name prefixes, registry paths, bucket names) from its single env input — never carry one environment's literal as "the" value. A hardcoded `-dev-` in shared code is invisible for as long as only dev exercises the path, and detonates the first time the *second* environment (usually the DR or prod path — the worst moment) reaches it. Storing a literal copy of a derivable value is the same defect in both cases: the copy and its source *will* diverge.

### 1.8 Why this shape *travels* — the bridge to Part 2

A quieter payoff of the emit-commands + stdout-canonical conventions: **a script's output is a clean stream, so execution can be *relocated*.** Because an action script writes its commands (or a renderer its content) to stdout, and takes its inputs from env/args rather than an interactive TTY, that stream can be piped **across an SSH tunnel (or an SSM session) to land execution on a remote host.**

But mind *what* travels down the pipe — and prefer, in this order:

1. **Data to a data-consumer** — `render.sh | kubectl apply -f -`, or `render.sh | ssh toolbox 'kubectl apply -f -'`. The content never meets a shell parser, so control-character / quoting / escaping problems simply don't arise. This is *why* §1.5 renders data rather than shell — it is the escaping-safe path; reach for it first.
2. **Commands to a shell via *stdin*** — `gen.sh | bash`, or `gen.sh | ssh toolbox bash`. Fed to stdin, the stream is parsed **exactly once**, by the executing shell — byte-identical to the local `| bash`. Keep the command *structure* well-quoted; never embed arbitrary values into it.
3. **Never `ssh toolbox "inline command …"`.** That form makes the *local* shell build a string and the *remote* shell parse it **again** — the double-parse that is quoting hell, leaks values into `argv`, and is the real target of the "just use Ansible" critique. The emit-to-stdin pattern exists precisely to sidestep it; the escaping pain people attribute to "shelling out over SSH" lives almost entirely in this third form, not the second.

**Secrets follow the execution locus.** Deferred `$VAR` expansion (§1.3) happens *wherever the final shell runs*, so for remote execution the secret must live **on the toolbox** — exactly where §2.4 already puts credentials. Resolve it there from a secret store; don't pipe it from the laptop. The A2 run is the proof: the conductor pulled its GitHub token from **Secrets Manager via its instance role** and used it on-box — no secret ever crossed the wire from the operator's machine.

This is what makes Part 2's **toolbox-as-execution-locus** practical: the operator's machine stays where you *read and approve* the plan; the toolbox is where it *runs* — identical toolchain, IAM-gated, audited. The Bash discipline isn't just hygiene; it's the mechanism that lets execution cross the laptop↔toolbox boundary without rewriting anything.

**The orchestrator is a stream too — not a resident monolith.** The same rule binds the *driver*, not only the leaf scripts: a bring-up/teardown should be expressible as a **flattened command stream piped to a bare `/bin/bash`** on the execution box, so the whole procedure is previewable and relocatable — *not* a big stateful program you copy onto the box and run in place (that's the thing this doctrine is meant to retire). **Honest caveat — repo, not fileless.** Terraform and Ansible are file-based: the modules, layers, playbooks, and manifests must be *present* on the execution host, so the box still needs the repo. Reconcile by separating the two concerns: **deliver the repo by a scoped `git clone`** (a single fine-grained, least-privilege token — never a clunky tree-ship through a side channel), and **drive the work as a piped stream**. The conductor that receives it is best kept **temporary, single-purpose, and per-account** (a disposable IaC distributor, minimal IAM perimeter) rather than a long-lived cross-account hub — smaller blast radius, and every run is reproducible from the same clone + stream.

### 1.9 Why bash here, not Ansible — collaboration and overhead

Two more strands of the same Part-1 ↔ Part-2 connective tissue — the *organisational* case for this shape, not only the technical one:

- **Decomposition for collaboration across seniority.** Breaking procedures into small, previewable, single-purpose scripts is a shared, replicable methodology a whole ops team can work in regardless of level. For **juniors**, the emitted preview is a chance to *see and understand* exactly what a procedure does before it runs. For **seniors**, it is an accessible, **auditable** sanity-check on every step — and a path toward genuinely *developing* tooling, not merely copying and consuming the most conventional off-the-shelf thing.
- **Lower overhead than a full-featured runner — and shell-portability.** No Python distribution to install and keep consistent across hosts; at most a newer **bash** on the *generator* box. And the bashisms stay **in the local generator** (the same split as §1.4 — complex bash local, output portable): the **emitted stream is a plain list of commands (or data) that almost any shell can run** — Bourne, bash, dash, busybox `ash`, zsh. So the *execution* host need not even be bash, which is exactly why the remote-piping above works without assuming the remote shell.

**The honest boundary.** Ansible (or any structured runner) earns its overhead when you need structured module transport instead of shell text, idempotency, secret injection that never touches `argv`, fact-gathering and inventory, or to assume *no* shell at all. The bash patterns own the large middle ground where **transparency, low overhead, and shell-portability** win — and where a human being able to *read the procedure before it runs* is worth more than the framework.

### 1.10 A script's claims are part of its contract — no masked failures

Everything a script *says* — its exit code, its log lines, its comments, its
phase names — is a claim someone downstream will act on. Three rules keep the
claims honest:

- **Never let a trailing suppressor vouch for the whole run.** An emitted stream
  that ends `… || true` makes the piped `bash` exit 0 over a *failed* bootstrap —
  the single worst failure mode, because the driver then reports success. If a
  step is genuinely optional, guard it explicitly (`if step; then …; fi`) *and
  say so in the emitted text*; otherwise let it fail and take the stream down
  with it (§1.2's `&&`-chaining exists for exactly this).
- **A phase that says it does X must do X — or fail.** A comment or
  `end_function` message claiming "installs the storage driver" over a body that
  doesn't is worse than no claim: it *masks* the failure until the one path
  (recovery, the second env) where it detonates. When a body changes, its
  claims are part of the diff.
- **Drivers preflight their invariants and leave a resume trail.** Assert the
  cheap structural invariants before spending anything (every layer declares
  `backend "s3"` — a missing block means silent *local* state); on any phase
  failure, print **which phase stopped, the exact resume command, and what was
  not reached**. The operator should never have to reconstruct "where was I?"
  from scrollback.

---

## Part 2 — Infrastructure management: patterns & operating model

These are the patterns first asserted while driving the A2 disaster-recovery exercise, extended since by the refactor arc (§2.3's environment model, §2.8's multi-account posture, §2.9). They sit on top of the Bash doctrine — most are *enforced by* scripts shaped as above.

### 2.1 Operations run from the toolbox, not the laptop (the standard)

> *(My framing, verbatim intent from the session:)* From pre-flight onward, the standard execution locus for infra/cluster operations is the **operator toolbox** — a pinned toolchain image — run either **in-cluster** once the cluster exists, or on a **one-off, disposable EC2** reached via **SSM (no inbound SSH)**.

Three goals this serves — important enough that they belong in every project's `CLAUDE.md`:

1. **Identical toolchain across all operators.** The entire toolset used to manage infrastructure is the same for everyone — fewer version conflicts; bootstrap, recovery, and deployment cycles stay consistent; **errors are reproducible and traceable.**
2. **Operator entry is IAM-gateable.** Authorization to *operate* can be gated by IAM (or GCP/Azure equivalents) and constrained to the toolbox itself — not scattered across laptops.
3. **All activity is auditable.** Toolbox operations, together with the identity that triggered them (via IAM / SSH-over-SSM / etc.), can be **logged and later audited.**

Realization detail learned the hard way: the toolbox must be **arm64 (Graviton `t4g.*`)** if the toolchain image is arm64 — don't default to `t2.*`. And give it the toolchain **self-contained** (install/build on the box) so it can bootstrap the very stack (e.g. the ECR registry) it would otherwise depend on — break the chicken-and-egg.

### 2.2 Self-contained, disposable layers

A control/ops resource (the "conductor") should be its **own Terraform layer** that owns **everything it needs** (its own VPC/subnet/IGW/SG/IAM) and reads **no other layer's state**, so it can be **applied and destroyed at any time without touching anything else**. **DRY is deliberately relaxed here** — a throwaway control box duplicating a little is worth the independence. Reach it via **SSM Session Manager** (public subnet + egress-only SG, *no* NAT, *no* VPC endpoints — the agent dials out; the operator dials in; nothing listens).

### 2.3 Terraform / GitOps division of labor

- **Terraform scaffolds infrastructure; ArgoCD configures Kubernetes; Ansible bootstraps app/host config.** Don't blur these.
- **Layered Terraform** (per Lee Briggs) with **single-source layers applied per environment** (one `stack/<cloud>/<layer>` tree + committed per-env tfvars; the driver composes the env-keyed remote-state backend at init). The dev→prod **promotion gate is separate *instances*** — distinct state, independent apply — **not duplicated source trees**: duplicated trees hand-drift, while per-env inputs keep real differences explicit. **Remote state** in S3 + DynamoDB lock. (Design detail + rationale: SPEC §3 / ADR-0020.)
- **GitOps via a single `ApplicationSet`** (not an app-of-apps root), with **sync waves** so operators land before the applications that need them.
- **Saved-plan workflow, always:** `tofu plan -out=FILE` → review → `tofu apply FILE`. **Never `-auto-approve`** (it re-plans fresh and can drift from what was reviewed).
- **Always ask before billable/mutating actions, per step.** Approval in one context does not carry forward to the next.

### 2.4 Identity, secrets, access

- **Authenticate with the instance profile** — e.g. CNPG/Barman → S3 via `inheritFromIAMRole`. Do **not** mint a second IAM user for what a role can do.
- **Pull-through registry credentials live in Secrets Manager** (ECR requires it); **non-secret config goes in Parameter Store.** Don't conflate the two. **Scope credentials to their job = no broader than needed — *not* one token per call.** A *single* fine-grained token scoped to exactly the jobs at hand is correct and preferable: e.g. one GitHub PAT carrying `read:packages` (GHCR pull-through) **and** Contents+Metadata read (repo clone) serves both the registry and the clone. The classic 403 (a `read:packages`-only token used to clone) was an **under-scoped** token, not a multi-purpose one — the fix is to scope it to *both* needs, not to split it into two.
- **Node access via SSH-over-SSM** (instance-id target, ProxyCommand tunnel) — **no inbound `:22`, no public API exposure** beyond a tight admin `/32`.

### 2.5 Cost posture

- **Spot while iterating, on-demand for the demo** (a `capacity_type` toggle) — and expect spot reclamation under regional pressure; the toggle earns its keep.
- **Managed NAT** for the PoC (documented trade-off).
- **Destroy compute between sessions**; **same-session up/down + automated reverse-order destroy** at delivery.

### 2.6 Disaster recovery & the ordering that matters

- **Recover before GitOps adopts.** Bring up the database operator **standalone** and run the restore **before** the app-of-apps/ApplicationSet would `initdb` an empty database. CNPG treats `spec.bootstrap` as immutable post-create, so the synced manifest later shows OutOfSync but does **not** wipe recovered data.
- **A backup that hasn't been restore-tested is a hope, not a backup.** Prove it with an exact **row-count acceptance target**, on a freshly-rebuilt stack, from the object store alone.
- **Standalone paths must install their own prerequisites.** The drill bypassed the wave-0 storage app, so the recovery cluster's gp3 PVCs would have hung Pending — the operator phase had to install the CSI driver + StorageClass itself. *Bypassing GitOps means inheriting GitOps's setup responsibilities.*

### 2.7 Teardown discipline — the orphans `tofu destroy` never sees

`tofu destroy` is necessary but **not sufficient**. A real teardown is **reverse dependency order** (apply-role work first, then admin for the trust anchor + state, since you're deleting the role you're using), **plus an explicit leak sweep**:

- **Orphans Terraform never created and can't see:**
  - **CSI-dynamically-provisioned EBS volumes** (the PVCs) — orphaned when nodes die.
  - **ECR pull-through *cache* repositories** — auto-created on first pull; not in any layer's state.
  - **Script-created Secrets Manager entries** (the pull-through creds) — they *survive* the layer destroy by design.
- **Guards that block a clean destroy:** ECR repos are **not** `force_delete` (empty them first); the state bucket has **`prevent_destroy`** (flip it, destroy, then restore the guard in committed code).
- **KMS can't go to zero instantly** — CMKs enter a **7-day-minimum pending-deletion window** (no charge meanwhile). Document them as "scheduled," not "gone."
- Standing leak-watch list: NAT gateways, unassociated EIPs, orphaned EBS, LoadBalancer Services, the state bucket/lock, and the above.

### 2.8 Supply chain (noted, to build out)

- **Scan stored images** (ECR enhanced scanning / Inspector, or Trivy in CI) with a documented **fail-on-critical** gate; Harbor's built-in Trivy scanning is the production-registry recommendation.
- **Centralize the scanning regime, then distribute by purpose (multi-account).** The reason to centralize a registry/cache in one *hub* account is not storage efficiency — it's a **single vulnerability-scanning gate** over everything the fleet pulls. Make the cross-account sharing **opt-in and least-privilege** (selected consumer accounts, scoped resource policies, per-purpose CMKs with explicit cross-account grants, prod-sensitive material never flowing into non-prod) — the **trust direction (who reads whom) is a bootstrap-time decision**, recorded, because it trades blast radius (a central account is a single point of compromise) for the gate. Distribute with **both** ECR modes, split by purpose: **pull** (a pull-through cache pointed at the hub) for the normal course, so downstream stays selective about versions/cadence; **push** (ECR registry **replication** from a scanned `release`/`hotfix` repo prefix) for security patches only, so no spoke lags on a fix. Mind the honest limit: replication delivers the *artifact* (fast, scanned, hub-provenanced); *adoption* still needs a deploy bump when repos are immutable + digest-pinned.

### 2.9 A claim needs an instrument — or it will rot

A stated property of the system ("the account id never lands in git", "every
layer uses remote state", "the manifests are schema-valid") is only as durable
as **the check that enforces it** — and it holds only over **the surfaces the
check actually covers**. The repo's own object lesson: the account-id-free
claim was true for everything its mechanism instrumented (manifests, tfvars,
rendered GitOps) and false for a channel nobody instrumented (terminal output
pasted into working notes), where the id sat in every commit until an audit
that *verified the claim instead of trusting it* caught it. Two rules follow:

- **Scope claims to their instruments.** Write "no account id in manifests or
  tfvars (enforced by X)", not "no account id in the repo" — or widen the
  instrument until the broad claim is true.
- **Give standing claims standing checks.** A one-time verification decays as
  the repo grows; hygiene claims belong in CI (gitleaks, validate, lint) where
  they re-verify on every change. Verify-don't-trust is the *audit* posture;
  instrument-don't-re-audit is the *steady-state* posture.

---

## Part 3 — `CLAUDE.md` seed (paste-ready, condensed)

> Drop into a new project's `CLAUDE.md`. Directive voice; trims the rationale above to rules an agent (or a new teammate) can follow.
>
> **Maintenance rule (this block is a rendered copy — §2.9 applies to it):** Part 3 condenses Parts 1–2; an edit to those sections is not done until this block is re-synced. It has drifted before.

```markdown
## Bash
- Draft against BashPitfalls. Never cargo-cult `set -euo pipefail`; use only flags you
  can explain (BashFAQ/105) and prefer explicit return-code checks. `set -o pipefail` is
  fine when a piped generator's failure must not be masked.
- **Two archetypes:** mutating/action scripts EMIT their commands to stdout (preview with
  `bash x.sh`, run with `bash x.sh | bash`, `&&`-chained, fail-fast); read-only/generator
  scripts run directly and emit a report/data with a meaningful exit code.
- **Sourceable `main()` pattern** (ref: ryderdain/bash/tests/destroy-tf-modules.sh):
  detect `(return 0 2>/dev/null) && is_sourced=true || is_sourced=false` first; put work
  in named functions; end each with `end_function "$?" msg` (return when sourced, exit
  when run directly); end the file with a dispatch block guarded by `is_sourced`. Composes
  with — does not replace — the emit convention.
- **Secrets — artifact carries references, not values:** emitted/reviewed text holds command
  structure + `$VAR` references; the value is resolved only by the EXECUTING shell from its own
  trusted source (env var locally; secret store on the toolbox), never embedded/transmitted.
  Hand-off creds via GIT_ASKPASS (off argv/.git/config/logs); "peek" as length+charset, never value.
- **Piping & remote execution:** prefer piping DATA to a data-consumer (`render.sh | kubectl apply
  -f -`) over piping commands to a shell; if commands, pipe to a shell via STDIN (`gen.sh | ssh host
  bash` — parsed once), NEVER `ssh host "inline…"` (double-parse, argv leaks). Secrets resolve at the
  execution locus. The ORCHESTRATOR is a stream too: a bring-up/teardown pipes a flattened command
  stream to a bare shell on the execution box — not a resident stateful program. File-based tools
  (tofu/ansible) still need the repo present: deliver it by a scoped `git clone` (one fine-grained
  least-priv token), never a tree-ship through a side channel; keep the receiving box (conductor)
  temporary, single-purpose, per-account.
- **Claims match behavior — no masked failures:** never end an emitted stream with `|| true`
  (a failed run must not exit 0 — if a step is optional, guard it explicitly AND say so);
  a comment/log/phase-name claiming X over a body that doesn't do X masks the failure until
  the worst path — claims are part of the diff. Drivers PREFLIGHT cheap invariants (e.g. every
  layer declares `backend "s3"`) and on phase failure print the stopped phase + exact resume
  command + phases not reached.
- **Automation completeness (stdout-canonical, file-as-argument):** a script whose point
  is producing content DEFAULTS to stdout (pipeable to `kubectl apply -f -` / `tee`);
  accepts a target path as an arg and ONLY THEN also writes the file (backup first),
  announcing the path on STDERR, while STILL emitting to stdout. Same shape for renderers,
  ARN→tfvars writers, and kubeconfig writers. No paste-back steps.
- **Dual-locus creds:** scripts must run with `AWS_PROFILE` (laptop) AND with instance-role
  creds (no profile) — never hard-require `AWS_PROFILE`.
- **Derive account- AND environment-bearing values.** Account-bearing: at runtime from the
  caller, or a gitignored auto-loaded file — never a per-run env var / shell memory.
  Env-bearing: shared code derives prefixes/paths from its single env input — a hardcoded
  `-dev-` literal in shared code detonates the first time the second env (DR, prod)
  exercises the path. Never store a literal copy of a derivable value.
- Bashisms over extra tools; enforce a minimum Bash version; snake_case files AND
  identifiers (unless a language-native convention governs).

## Operations & infrastructure
- **Run operations from the toolbox, not the laptop** — a pinned toolchain image, in-cluster
  or on a one-off SSM-reached EC2 (arm64/t4g if the image is arm64; no inbound SSH). Goals:
  (1) identical toolchain across operators → reproducible/traceable errors; (2) IAM-gateable
  operator entry; (3) auditable activity (operation + triggering identity).
- **Self-contained disposable control layer** (e.g. `00-conductor`): owns its own
  VPC/IAM/etc., reads no other layer's state, deploy/destroyable in isolation. DRY relaxed.
- **Terraform scaffolds infra; ArgoCD (single ApplicationSet + sync waves) configures k8s;
  Ansible bootstraps host/app.** Layered TF with SINGLE-SOURCE layers + committed per-env
  tfvars (driver composes the env-keyed backend at init); the promotion gate is separate
  INSTANCES (state + apply), never duplicated source trees. Remote state (S3+DDB lock).
- **Saved-plan workflow always** (`plan -out` → review → `apply FILE`); never `-auto-approve`.
  Always ask before billable/mutating actions, per step.
- **Instance-profile auth** (no second IAM user). Pull-through creds → Secrets Manager;
  non-secret config → Parameter Store. **Scope credentials to their job = no broader than
  needed, NOT one-token-per-call**: one fine-grained token covering exactly the jobs at
  hand (e.g. one PAT: `read:packages` + Contents/Metadata read) beats splitting; the classic
  403 is an UNDER-scoped token, not a multi-purpose one. Node access via SSH-over-SSM
  (no inbound :22).
- **Cost:** spot iterating / on-demand demo; managed NAT; destroy compute between sessions.
- **DR:** recover the DB operator + restore STANDALONE before GitOps would initdb an empty
  DB; prove with an exact row-count target on a freshly-rebuilt stack; a standalone path
  installs its own prerequisites (e.g. CSI + StorageClass).
- **Teardown = reverse-order destroy + explicit leak sweep.** `tofu destroy` misses:
  CSI-dynamic EBS volumes, ECR pull-through CACHE repos, script-created secrets. ECR repos
  aren't force_delete (empty first); state bucket has prevent_destroy (flip + restore); KMS
  CMKs go to a 7-day pending-deletion window, not instant.
- **Supply chain:** scan stored images (ECR scanning / Inspector / Trivy), fail-on-critical;
  Harbor (built-in Trivy) as the prod registry recommendation. Multi-account: centralize the
  SCAN GATE in a hub registry/cache (that's the reason to centralize — not storage), share
  least-priv/opt-in, trust direction decided + recorded at bootstrap; distribute via pull
  (pull-through cache, downstream stays version-selective) for the normal course + push
  (registry replication from a scanned release/hotfix prefix) for security fixes only.
- **Claims need instruments:** scope any stated property ("no account id in git", "manifests
  schema-valid") to the surfaces a CHECK actually covers, and give standing claims standing
  CI checks — a one-time verification decays; verify-don't-trust when auditing,
  instrument-don't-re-audit in steady state.
```

---

## Appendix — the concrete moments these abstractions came from

- **ghcr PAT 403 on clone** → the token was **under-scoped** (`read:packages` only, used to clone), not "the wrong token" — the durable fix is **one fine-grained PAT scoped to *both* jobs** (packages + Contents/Metadata read), per §2.4. Worked around at the time by shipping the tree through the state bucket (no GitHub cred); that tree-ship is the clunky path now being replaced by the scoped `git clone` (§1.8).
- **`helm --wait` false-negative on CRDs** → wait on `kubectl wait --for=condition=Available`, not the chart, when CRDs lack `observedGeneration`.
- **Dex `$VAR` not expanded in `staticClients[].secret`** → know which fields your tool templates; `secretEnv:` vs `$VAR`.
- **Broken multi-arch push (arm64 child 404s)** → build from source + import natively.
- **40-ecr `RepositoryNotEmpty` / bootstrap `prevent_destroy`** → teardown guards are real; plan for them.
- **3 orphaned gp3 EBS volumes + ECR cache repos after `tofu destroy`** → the leak sweep is not optional.
- **`gitops` phase reported success over a dead API tunnel** → the emitted stream ended `kubectl patch … || true`, so the piped `bash` exited 0 and the driver vouched for a failed bootstrap (§1.10's first rule, learned live).
- **`operator()` claimed the EBS CSI + gp3 install its body never did** → an honest-looking comment + a hedged `end_function` message masked a DR-only failure: recovery-cluster PVCs would hang Pending. Fixed by making the phase *do* what it says (render the same committed values GitOps uses) and assert the StorageClass exists (§1.10's second rule).
- **`if ! cmd; then rc=$?` captured `0` for a failing `cmd`** → the negation *is* the tested command, so `$?` holds the `!`-inverted status. Capture first (`cmd; rc=$?`), then branch — a BashPitfalls-class trap found in the driver's own resume logic.
- **`brzl-dev-k8s` hardcoded in shared values; the standalone DR path consumed it** → prod recovery would have pulled images through the *dev* cache repos. Invisible until the second env exercised the path; fixed by deriving the prefix from the env input (§1.7's generalisation, verbatim).
- **The account id sat in `notes/` for the repo's whole history while ADR-0016 said "never lands in git"** → the claim was true over the instrumented surfaces (manifests, tfvars) and false over an uninstrumented channel (pasted terminal output). Caught only by an audit that verified instead of trusted (§2.9, verbatim).
