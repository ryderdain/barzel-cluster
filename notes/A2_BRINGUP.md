# A2 — Full AWS Bring-up + DR Restore — command-by-command – with notes

ATTN: CLAUDE: I have edited this file with my notes and feedback; I'm preceding my notes with `#### START` and ending them with `#### END`. Each note refers to the section preceding it.

## RESOLUTION LOG (Claude → your notes, 2026-06-08)

Each `#### START … #### END` note below was actioned. The raw manual commands are kept
as the *underlying reference*; the procedure is now **driven from a disposable conductor
via `gitops/tools/a2_restore.sh`** (your Q1 + Q2 + Q3 answers).

- **(0.4) export the role once / `set -u` care** → on a laptop `export AWS_PROFILE=brzl-apply`
  once; on the **conductor** there is NO profile (instance-role creds). Every script now
  works both ways (it never hard-requires `AWS_PROFILE`; `runlib.sh::aws_profile_note`
  reports which is in use). The scripts avoid `set -u` pitfalls (explicit `${x:-}` guards).
- **(0.5) `create_pullthrough_secrets.sh` → tfvars + sourceable** → refactored: emit step
  unchanged (tokens never printed); new `write_arns_to_tfvars` resolves the ARNs and
  writes `40-ecr/terraform.tfvars` (backs it up first) — no more paste-back. Adopts the
  sourceable `main()` pattern (per `ryderdain/bash/tests/destroy-tf-modules.sh`).
- **(Part 1) toolbox as execution locus** → built as a self-contained **`00-conductor`**
  layer (own VPC/subnet/IGW, t4g Graviton — the toolbox is arm64, **not** t2 —, SSM-only
  no inbound, inline IAM; fully deploy/destroyable without touching any other layer). The
  3 goals are now a standing decision in **CLAUDE.md**.
- **(Part 3) image vuln scanning** → noted in **PLAN.md** tomorrow's backlog (ECR enhanced
  scanning / Trivy gate; Harbor as the prod recommendation). Not implemented today.
- **(Part 6) drop the `sed`** → new `gitops/operators/postgres/render_recovery_manifest.sh`
  renders the manifest (`bash render… | kubectl apply -f -`); the driver's `recover` phase
  uses it.
- **(Part 7) app-of-apps?** → **corrected**: ADR-0016 switched us to a single
  **ApplicationSet**. Wording fixed here and in `bootstrap_argocd.sh`.

## HOW TO RUN IT NOW (conductor + driver)

```sh
# 1. Stand up the conductor (💸 ~$0.40/day; saved-plan, gated):
cd terraform/environments/dev/00-conductor
cp ../backend.hcl ./ 2>/dev/null; : # uses ../backend.hcl
AWS_PROFILE=brzl-apply tofu init -backend-config=../backend.hcl
AWS_PROFILE=brzl-apply tofu plan -out=tfplan      # review
AWS_PROFILE=brzl-apply tofu apply tfplan
AWS_PROFILE=brzl-apply tofu output ssm_session_command   # copy it

# 2. Enter the conductor (no SSH; SSM only) and run the gated driver:
aws ssm start-session --target <conductor-instance-id>
#   (on the box) cd /opt/brzl && git clone <repo> brzl-demo && cd brzl-demo
#   cp terraform/environments/dev/backend.hcl.example terraform/environments/dev/backend.hcl  # set bucket
bash gitops/tools/a2_restore.sh preflight   # FREE
bash gitops/tools/a2_restore.sh layers      # 💸 10→50, per-layer saved-plan + confirm
bash gitops/tools/a2_restore.sh images      # 💸 push demo-app
bash gitops/tools/a2_restore.sh cluster     # k3s (gated) + kubeconfig
bash gitops/tools/a2_restore.sh operator    # standalone CNPG
bash gitops/tools/a2_restore.sh recover     # render + apply recovery + wait
bash gitops/tools/a2_restore.sh verify      # FREE: 4/84/423/84 acceptance
# teardown: bash gitops/tools/a2_restore.sh teardown   (keeps 15-kms) then destroy 00-conductor
```

The per-`Part` manual commands below remain the source-of-truth reference for what each
driver phase does.

> **For my own use/review only.** Not a deliverable (the polished operator-facing
> version is `docs/BOOTSTRAP.md` + `docs/RECOVERY.md`). This file is the *complete*
> linear sequence with every command spelled out, including the one-time
> foundational steps that are **already done** for this account (those are
> **commented out**, tagged `[ONE-TIME — DONE]` / `[ONE-TIME — would-run on a fresh account]`).
>
> **What's already standing (so most of Part 0 is commented):** AWS account
> `578456618578`, the Terraform **state backend** (S3 `brzl-demo-tfstate-578456618578`
> + DynamoDB `brzl-demo-tflock` + state CMK), the **identity** trust anchor
> (`brzl-tofu-plan` / `brzl-tofu-apply` roles), and the **`15-kms` foundation**
> (EBS CMK, backup CMK, **the CNPG backup bucket that still holds the dataset**)
> were all left up at teardown. **A2 = re-stand `10`→`50`, recover Postgres from
> the surviving S3 backup, verify the row counts, then tear back down.**
>
> **Guardrails (CLAUDE.md):** every `tofu apply`/`destroy` is the **saved-plan**
> workflow — `tofu plan -out=tfplan` → review → `tofu apply tfplan` (never
> `-auto-approve`). All AWS ops run under the **assumed apply role**
> (`AWS_PROFILE=brzl-apply`). `ansible-playbook` against real hosts and any
> mutating `aws`/`kubectl delete`/`helm uninstall` are **gated** — confirm before
> running. Mutating emit-commands scripts are previewed (`bash x.sh`) before
> `| bash`.

---

## Conventions used below

```sh
# Run everything in this file from the repo root unless a `cd` says otherwise.
# The apply role is reached via an AWS CLI *profile* (~/.aws/config), so commands
# read `AWS_PROFILE=brzl-apply` rather than exporting STS env vars by hand.
#
# ~/.aws/config should contain (ONE-TIME — DONE):
#   [profile brzl-apply]
#   role_arn       = arn:aws:iam::578456618578:role/brzl-tofu-apply
#   source_profile = default              # the admin/long-lived creds
#   region         = eu-central-1
#
# Sanity check the role assumption resolves before doing anything billable:
AWS_PROFILE=brzl-apply aws sts get-caller-identity   # → .../brzl-tofu-apply/...
```

---

# PART 0 — Foundational bootstrap (ONE-TIME; mostly DONE → commented)

Everything in Part 0 is what you'd run to stand the account up **from absolutely
nothing**. For A2 it's already in place, so it's commented. Kept here for
completeness / the "fresh account or new region" disaster-recovery path.

## 0.1 — AWS account + admin identity  `[ONE-TIME — DONE]`

```sh
# # Create / sign into the AWS account; create an admin IAM user or use Identity
# # Center. Configure the long-lived "default" profile the apply role sources from:
# aws configure                         # access key, secret, region=eu-central-1
# aws sts get-caller-identity           # confirm you're the admin
#
# # Capture the account id (every derived name keys off it — never hard-code it):
# aws sts get-caller-identity --query Account --output text   # → 578456618578
```

## 0.2 — Local SSH key for break-glass node access  `[ONE-TIME — superseded]`

```sh
# # NOTE: the node SSH key pair is now GENERATED BY OPENTOFU (50-compute/secrets.tf:
# # tls_private_key → aws_key_pair → local_sensitive_file). You do NOT supply a
# # public key anymore. Day-to-day node access is SSH-over-SSM (no :22 ingress).
# # A personal admin key is only needed if you flip enable_ssh_ingress=true for
# # break-glass:
# ssh-keygen -t ed25519 -f ~/.ssh/brzl_admin -C "brzl break-glass"
```

## 0.3 — Terraform state backend  `[ONE-TIME — DONE, still up]`

```sh
# # Creates the S3 state bucket (versioned, CMK-encrypted, private) + DynamoDB lock.
# # Run as ADMIN (this predates the apply role). ~$1/mo for the CMK; storage ~$0.
# cd terraform/bootstrap
# cp terraform.tfvars.example terraform.tfvars   # set state_bucket_name = brzl-demo-tfstate-578456618578
# tofu init
# tofu plan -out=tfplan                          # review
# tofu apply tfplan
# # Record outputs into every env's backend.hcl (copy from backend.hcl.example):
# #   state_bucket / lock_table / state_kms_key_arn
# cd ../..
```

## 0.4 — Identity / trust anchor (OIDC + scoped roles)  `[ONE-TIME — DONE, still up]`

```sh
# # GitHub Actions OIDC provider + least-priv brzl-tofu-plan / brzl-tofu-apply
# # roles. Run as ADMIN. After this, every later phase assumes the apply role.
# cd terraform/identity
# cp backend.hcl.example backend.hcl             # real bucket name (gitignored)
# cp terraform.tfvars.example terraform.tfvars   # operator_principal_arns = your IAM user ARN
# tofu init -backend-config=backend.hcl
# tofu plan -out=tfplan                          # review
# tofu apply tfplan
# cd ../..
# # (Optional, manual, not Terraformed) enable IAM Identity Center for human SSO.
# # Smoke test: assume the PLAN role → reads allowed, writes denied.
```
#### START
As all follwing actions will use the same role, it should be exported into the environment to be consumed when running successive commands rather than specified each time. Take a moment to sanity-check all commands (and scripts) will run appropriately (keeping in mind that `set -u` on scripts would require injecting the AWS_PROFILE value again).
#### END

## 0.5 — Registry pull-through credentials (image supply chain)  `[recreate IF the secrets were swept]`

These are **core supply chain** (not SSO): ghcr.io (CNPG, external-secrets),
Docker Hub (Grafana, kube-prometheus-stack), quay.io (ArgoCD — credential-free but
the cache repo is provisioned the same way). They are **Secrets Manager** entries
(ECR pull-through can't use Parameter Store), script-created (not `40-ecr`-managed),
so they normally **survive** a `40-ecr` destroy. Step 0 of Part 2 checks; recreate
only if missing.

```sh
# # The upstream creds (NEVER in git): GitHub user + read:packages PAT; Docker Hub
# # user + read-only token. quay needs none.
# export GHCR_USERNAME=...      GHCR_TOKEN=...
# export DOCKERHUB_USERNAME=... DOCKERHUB_TOKEN=...
# AWS_PROFILE=brzl-apply bash gitops/bootstrap/create_pullthrough_secrets.sh        # PREVIEW
# AWS_PROFILE=brzl-apply bash gitops/bootstrap/create_pullthrough_secrets.sh | bash # RUN
# # → copy the printed ARNs into 40-ecr tfvars (ghcr_credential_arn /
# #   dockerhub_credential_arn / quay_credential_arn) before applying 40-ecr.
```

#### START
The `create_pullthrough_secrets.sh` script should also return the ARNs and populate the approprate tfvars file. It's a drag on automation that user intervention is required here.
Also, this particular script should be set up as a function and called here as `main()` . I have a pattern to read (which should be folded into bash scripts as appropriate going forward), to allow executing each script directly, or as a source to include in a separate calling script; see that pattern demonstrated in the script `/Users/rdain/Local/github.com/ryderdain/bash/tests/destroy-tf-modules.sh`
The reason to set up these individual action scripts in this manner is to make it possible to have an orchestration script call complex actions in a clear and consistent manner for juniors who will be aided by the overall pattern, which fits together with the guardrails for mutating bash scripts pattern which you've already mentioned above in in your preamble.
#### END

## 0.6 — GitOps repo deploy key  `[ONE-TIME — DONE; the in-cluster Secret is reapplied at GitOps bring-up]`

```sh
# # Read-only ed25519 deploy key; public half on the GitHub repo (Settings → Deploy
# # keys, NO write). The private half lives in the gitignored repo-deploy-key.yaml,
# # which bootstrap_argocd.sh applies as an in-cluster Secret.
# ssh-keygen -t ed25519 -f gitops/bootstrap/brzl_demo_deploy_key -C "brzl argocd ro" -N ""
# #  → add gitops/bootstrap/brzl_demo_deploy_key.pub to GitHub deploy keys
# cp gitops/bootstrap/repo-deploy-key.example.yaml gitops/bootstrap/repo-deploy-key.yaml
# #  → paste the private half into repo-deploy-key.yaml (gitignored)
```

## 0.7 — Docker Hub login on the apply host (for image builds)  `[as needed at build time]`

`40-ecr`'s `toolbox.tf` rebuilds+pushes the toolbox image, and `apps/demo-app/build_push.sh`
builds the demo-app — both need a working docker/buildx on the apply host. ECR auth
itself is via `aws ecr get-login-password` (no Docker Hub login required to *push*
to ECR), but pulling public base layers during the build can hit Docker Hub
anonymous rate limits.

```sh
# # Only if you hit Docker Hub pull-rate limits during the image builds:
# docker login -u "$DOCKERHUB_USERNAME"           # paste the read-only token
# # To skip the toolbox rebuild entirely during 40-ecr apply, set in 40-ecr tfvars:
# #   toolbox_build_enabled = false
```

## 0.8 — Operator-SSO pre-staging (OPTIONAL layer — NOT part of A2)  `[skip for A2]`

> **Out of scope for A2 and for the AWS core deliverable.** The Dex/oauth2-proxy/
> cert-manager SSO gateway is **local-k3d-only** (`gitops/clusters/local/sso/`); the
> AWS ApplicationSet never deploys it. Listed here only so the pre-staging is not
> confused with the core supply-chain creds above. None of this is needed to bring
> up the AWS cluster or run the DR restore.

```sh
# # [OPTIONAL — local SSO only] GitHub OAuth App (callback https://dex.sso.barzel.sh/callback),
# # FreeDNS (afraid.org) credential for the DNS-01 webhook, /etc/hosts entries, and:
# # AWS_PROFILE= bash gitops/bootstrap/create_sso_secrets.sh | bash   # in-cluster Secrets
# # Promoting SSO to AWS would mean: point *.sso.barzel.sh A-records at the NLB and
# # add the kube-apiserver OIDC args to the Ansible kubernetes role. Documented, not built.
```

---

# PART 1 — Pre-flight (FREE, run first)

Confirm the surviving foundation + the backup objects are intact **before** spending
a cent on compute. Nothing here mutates.

```sh
# Apply role resolves?
AWS_PROFILE=brzl-apply aws sts get-caller-identity

# The 15-kms foundation is still up and the dataset is in S3?
AWS_PROFILE=brzl-apply aws s3 ls \
  "s3://$(AWS_PROFILE=brzl-apply aws ssm get-parameter \
      --name /brzl-dev/backup/bucket_name --query Parameter.Value --output text)/pg/base/" \
  --recursive | tail
#  → expect the pre-teardown base backup (…/pg/base/20260604T183915/ data.tar.gz + backup.info)

# Pull-through cred secrets survived the teardown? (recreate via 0.5 only if absent)
AWS_PROFILE=brzl-apply aws secretsmanager list-secrets \
  --query "SecretList[?starts_with(Name,'ecr-pullthroughcache/')].Name"
#  → expect ecr-pullthroughcache/brzl-dev-{quay,github,dockerhub}

# backend.hcl present in dev/ (gitignored; copied once from backend.hcl.example)?
test -f terraform/environments/dev/backend.hcl && echo "backend.hcl OK" || \
  echo "MISSING: cp terraform/environments/dev/backend.hcl.example terraform/environments/dev/backend.hcl and set the real bucket"
```
#### START
From the point of the pre-flight onwards, all actions should be run in the pattern of being executed from the _toolbox_, rather than in the pattern of a user from their laptop. The toolbox can be run from within a t2.small (or possibly t2.medium, given the resource demands of docker, needs a one-time assessment) one-off Ec2 image which runs in its own, or within the same VPC as the k3s cluster. While more complicated during bootstrap (as it may require setting up additional minimal resources, such as a temporary VPC with SSM-over-SSH enabled), as long as the baseline account and terraform management is available this should be possible. Let me know if you run into issues. 
Setting things up with this pattern acheives three goals I have laid out for myself as standards for operations and infrastructure; this is important enough to retain in CLAUDE.md. 
- The entire toolchain used to manage infrastructure will remain identical between different operators; reduces versioning conflicts and keeps the bootstrap, recovery, and deployment cycles all consistent, making errors easier to trace.
- Entry into operational roles can be more easily gated by IAM or other permission structures (e.g., on GCP or Azure), securing access and constraining authorization to the toolbox itself.
- All activity can be logged and audited on the basis of the toolbox's operations, together with the user triggering those actions (based on the IAM or authorization to use SSH-over-SSM, or other methods), and later audited if necessary. 
#### END
---

# PART 2 — Infrastructure layers 10 → 50  💸 (BILLABLE; saved-plan, gated, in order)

The apply order is `10-network → 15-kms → 20-security → 30-iam → 40-ecr → 50-compute`.
**`15-kms` is already up** (it was retained) — its `apply` is a no-op/in-place and
safe to run for idempotence, but you can skip it. `30-iam` reads `15-kms` (backup
grants); `50-compute` reads `15-kms` (EBS CMK).

**Per layer**, the saved-plan workflow — confirm each plan before its apply:

```sh
# One layer at a time. DO NOT loop-and-auto-apply — review each plan first (guardrail).
cd terraform/environments/dev/10-network
AWS_PROFILE=brzl-apply tofu init -backend-config=../backend.hcl
AWS_PROFILE=brzl-apply tofu plan -out=tfplan          # ← review the plan output
AWS_PROFILE=brzl-apply tofu apply tfplan              # ← gated: confirm, then apply
cd ../../../..
```

Repeat the identical four-command block for each subsequent layer (only the `cd`
target changes). The mapping of what each creates:

| layer | creates | notes |
|-------|---------|-------|
| `10-network` | VPC, public subnets (1/AZ), IGW, route tables, **1× NAT gw** 💸 | NAT is the main idle cost |
| `15-kms` | EBS CMK, backup CMK, **CNPG backup bucket** | **already up** — apply is no-op; skippable |
| `20-security` | cluster SG (node↔node, API 6443, NodePort), SSH/API locked to admin /32 | needs `TF_VAR_mycurrentip` if your IP moved (see below) |
| `30-iam` | node IAM role + instance profile (`brzl-dev-node`), S3+backup-KMS + SSM grants | reads 15-kms |
| `40-ecr` | demo-app + helm-charts repos, pull-through caches, ECR CMK, **rebuilds+pushes toolbox** 💸 | needs `*_credential_arn` tfvars from 0.5; `toolbox_build_enabled=false` to skip the image build |
| `50-compute` | **3× m6g.large** 💸, EBS volumes, TF-generated keypair, instance profiles 1/AZ | `capacity_type=on-demand` for the demo (spot got reclaimed 2026-06-02) |

```sh
# If your public IP changed since last time, the admin /32 lock in 20-security needs it:
export TF_VAR_mycurrentip="$(curl -s -4 icanhazip.com)"   # consumed by 20-security's plan/apply

# For the delivery demo use on-demand (spot was reclaimed under eu-central-1 pressure).
# Set in 50-compute/terraform.tfvars (gitignored) OR export:
export TF_VAR_capacity_type="on-demand"   # 50-compute reads this; "spot" for cheap iteration

# Checkpoint after 50-compute:
cd terraform/environments/dev/50-compute && AWS_PROFILE=brzl-apply tofu output && cd ../../../..
#  → 3 instance ids + private/public IPs listed → infra live.
```

---

# PART 3 — Image supply chain into ECR

`40-ecr` already (re)pushed the **toolbox** during its apply (unless you disabled
it). The **demo-app** image must be pushed before the app would run — though for the
*DR drill proper* (Parts 4–6) only Postgres + the recovery cluster matter, the
demo-app image is needed if you go on to the optional full-GitOps cutover (Part 7).

```sh
# Preview then push the arm64 demo-app image to ECR (emit-commands; review then pipe):
AWS_PROFILE=brzl-apply bash apps/demo-app/build_push.sh                 # PREVIEW
set -o pipefail; AWS_PROFILE=brzl-apply bash apps/demo-app/build_push.sh | bash   # RUN
#  → ECR login → docker buildx (arm64) → push brzl-dev/demo-app:<tag> → verify manifest
```
#### START
One loose item we skipped over was performing vulnerability scans on stored images in ECR (or Harbor). We don't need a full implementation today, but make a note of it for PLAN.md along with the other items tomorrow.
#### END

---

# PART 4 — k3s on the nodes + local kubeconfig  (GATED — real hosts)

Terraform provisioned the boxes; Ansible configures them and installs k3s
(`bootstrap.yml` = base+security prep, `cluster.yml` = the `kubernetes` role / k3s HA).
**`ansible-playbook` against real hosts is gated — confirm before running.**

```sh
cd ansible

# Render the inventory from the live 50-compute outputs (reads instance-ids for SSH-over-SSM):
AWS_PROFILE=brzl-apply bash inventory/generate-inventory.sh > inventory/dev.yml
cat inventory/dev.yml         # eyeball: 3 hosts under k3s_servers, one marked primary

# 4a. Node prep (base + security roles). GATED.
ansible-playbook playbooks/bootstrap.yml

# 4b. k3s HA install (kubernetes role: primary --cluster-init, then joiners; fetches kubeconfig). GATED.
ansible-playbook playbooks/cluster.yml
cd ..

# Install/refresh the LOCAL kubeconfig (re-resolves the current primary endpoint — node
# IPs drift when compute is recreated). Writes ~/.kube/config (backs it up first):
AWS_PROFILE=brzl-apply bash gitops/tools/kubeconfig_setup.sh
kubectl get nodes            # → 3 Ready  ✅ cluster checkpoint
```

---

# PART 5 — CloudNativePG operator (standalone for the drill)

Install the operator **standalone** (not via the app-of-apps) so the DB is recovered
*before* ArgoCD's synced manifest would `initdb` an empty `pg`. This is the key
"recover first, adopt into GitOps later" ordering.

```sh
# The CNPG operator chart (ghcr-backed images already routed via pull-through):
helm upgrade --install cnpg-operator cnpg/cloudnative-pg \
  --version 0.28.2 -n cnpg-system --create-namespace
# Wait on the DEPLOYMENT (not helm --wait — the CRD install false-negatives on kstatus):
kubectl -n cnpg-system wait --for=condition=Available deploy --all --timeout=300s
kubectl create namespace cnpg-demo
```

---

# PART 6 — Recover from S3 + verify the acceptance target

The standalone recovery manifest `gitops/operators/postgres/cluster-recovery.yaml`
bootstraps a NEW cluster from the retained object store: it **recovers from
`serverName: pg`** and **archives its own fresh WAL under `serverName: pg-restore`**,
so the original backups stay pristine and the drill is repeatable. Two sentinels are
resolved from SSM at apply (the ECR host for the operator image, the backup bucket).

```sh
# Render (resolves both SSM sentinels) + apply — the sed is gone; the renderer is the
# single previewable step (driver phase: `a2_restore.sh recover`):
bash gitops/operators/postgres/render_recovery_manifest.sh                 # PREVIEW
bash gitops/operators/postgres/render_recovery_manifest.sh | kubectl apply -f -   # APPLY

# Wait for the recovery to reach a healthy primary:
kubectl -n cnpg-demo wait \
  --for=jsonpath='{.status.phase}'='Cluster in healthy state' cluster/pg --timeout=600s
kubectl -n cnpg-demo get cluster
# (deeper view) kubectl cnpg status pg -n cnpg-demo

# THE acceptance check — counts must match exactly:
primary="$(kubectl -n cnpg-demo get pod \
  -l cnpg.io/cluster=pg,cnpg.io/instanceRole=primary -o name)"
kubectl -n cnpg-demo exec "$primary" -- psql -U postgres -d app -tAc \
  "select 'items',count(*) from items union all select 'searches',count(*) from searches \
   union all select 'search_results',count(*) from search_results \
   union all select 'api_calls',count(*) from api_calls;"
```
#### START
The use of `sed` here is clunky and introduces too much cognitive overhead. Adopt the guardrails method for `bash`, and generate an additional script here to output the appropriate manifest for piping into `kubectl apply -f -` ; that makes the `bash x.sh | <exec>` pattern more consistent and easier to follow by a human user.

This is a good point to mention: prior to running the plan, read this document until you understand my notes, especially my guidance around how to set up scripts (ask questions if anything is vague or requires clarification). Rather than executing all the commands in order for A2, generate appropriate user scripts which can be executed by an operator from their laptop or from within the toolbox (preferring the latter, as it's the goal anyway), and run the A2 procedure using these new scripts.
#### END

**PASS when:**

| table            | expected |
| ---------------- | -------- |
| `items`          | 4        |
| `searches`       | 84       |
| `search_results` | 423      |
| `api_calls`      | 84       |

Counts match → **DR proven.** Flip `docs/RECOVERY.md` "Database restore / PITR" +
the DR-test block to ✅, and tick PLAN.md Fri-Jun-5 "Restore: perform + verify".

---

# PART 7 — (OPTIONAL) Full GitOps adoption + app cutover

Only if you want the recovered DB serving the live app (beyond proof). CNPG treats
`spec.bootstrap` as immutable post-create, so the **ApplicationSet's** synced Postgres
`Cluster` (`initdb`) manifest shows **OutOfSync but does NOT wipe** the recovered data.
(ADR-0016 — a single ApplicationSet, not an app-of-apps root.)

```sh
# # Bootstrap ArgoCD as normal (emit-commands; review then pipe):
# AWS_PROFILE=brzl-apply bash gitops/bootstrap/bootstrap_argocd.sh         # PREVIEW
# AWS_PROFILE=brzl-apply bash gitops/bootstrap/bootstrap_argocd.sh | bash  # RUN
# # Settle the bootstrap diff: commit the recovery variant, or annotate the Cluster so
# # ArgoCD stops trying to reconcile spec.bootstrap. Then the demo-app reads the
# # recovered Postgres end-to-end (POST/GET /items, /search).
# # Web UIs (zero-cost port-forward): bash gitops/tools/ui_forward.sh
```
#### START
This should be answered first: didn't we switch to using the ApplicationSet methodology rather than the app-of-apps pattern?
#### END

---

# PART 8 — Tear back down (stop billing)  💸→0  (GATED)

Reverse order; **keep `15-kms`** (CMKs + the backup bucket — the data must survive
for the *next* drill). Saved-plan `destroy` per layer.

```sh
# Per layer, in REVERSE order: 50-compute → 40-ecr → 30-iam → 20-security → 10-network
cd terraform/environments/dev/50-compute
AWS_PROFILE=brzl-apply tofu plan -destroy -out=tfplan   # ← review what gets destroyed
AWS_PROFILE=brzl-apply tofu apply tfplan                # ← gated destroy
cd ../../../..
# … repeat for 40-ecr, 30-iam, 20-security, 10-network.
# 40-ecr destroy: the repos may need force-empty (force_destroy) — its config handles it,
#   but the pull-through SECRETS are script-created and survive (good — Part 0.5 stays done).
# DO NOT destroy 15-kms.

# Manual leak sweep (terraform destroy misses these — CLAUDE.md cost-leak watch):
AWS_PROFILE=brzl-apply aws ec2 describe-nat-gateways --filter Name=state,Values=available --query 'NatGateways[].NatGatewayId'
AWS_PROFILE=brzl-apply aws ec2 describe-addresses --query 'Addresses[?AssociationId==null].AllocationId'   # unassociated EIPs
AWS_PROFILE=brzl-apply aws ec2 describe-volumes --filters Name=status,Values=available --query 'Volumes[].VolumeId'  # orphaned EBS behind PVCs
AWS_PROFILE=brzl-apply aws elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerArn'          # stray LB Services
# Intentionally LEFT (not leaks): the 15-kms CMKs + backup bucket, ECR images, S3 backups.
```

---

## Quick "happy path" for the A2 run (the non-commented essentials, in order)

1. **Pre-flight** (Part 1): `sts get-caller-identity` · S3 backup present · pull-through secrets present · `backend.hcl` present.
2. **Layers** (Part 2): `10 → (15 skip/no-op) → 20 → 30 → 40 → 50`, each `init` → `plan -out` → review → `apply tfplan`. Set `TF_VAR_capacity_type=on-demand`, refresh `TF_VAR_mycurrentip` if moved.
3. **demo-app image** (Part 3) — only needed for the Part 7 cutover; skip for proof-only.
4. **k3s** (Part 4, gated): `generate-inventory.sh` → `bootstrap.yml` → `cluster.yml` → `kubeconfig_setup.sh` → `kubectl get nodes` = 3 Ready.
5. **CNPG operator** (Part 5): helm install → `kubectl wait` → create `cnpg-demo` ns.
6. **Recover + verify** (Part 6): resolve sentinels → `kubectl apply` recovery → `wait` healthy → count check (4 / 84 / 423 / 84).
7. **Teardown** (Part 8, gated): reverse-order saved-plan destroy, keep `15-kms`, leak sweep.

#### START
Run a pass to generate the scripts as requested. We can start the A2 procedure as soon as these are ready.
#### END