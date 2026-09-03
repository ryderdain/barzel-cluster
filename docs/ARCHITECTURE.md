# Architecture & Design Decisions

The delivery-facing design document for this platform: what it is, how the
pieces fit, **why the load-bearing choices were made**, and a running
[Architecture Decision Record](#architecture-decision-records-adrs) log at the
bottom.

> The top-level [`README.md`](../README.md) is the front door — read it for the
> at-a-glance picture and the step-by-step reproduce/teardown instructions. This
> document is the rationale layer beneath it. Operational procedures live in the
> runbooks: [`BOOTSTRAP`](BOOTSTRAP.md) · [`ACCESS`](ACCESS.md) ·
> [`UPGRADE`](UPGRADE.md) · [`RECOVERY`](RECOVERY.md) · [`TEARDOWN`](TEARDOWN.md).

## 1. What this is

A GitOps-driven, reproducible, secure-by-default platform that takes a single
cloud account from nothing to a running stateful service:

```
                 ┌─ admin (once) ─┐
                 │  bootstrap:    │  state backend (S3 + DynamoDB lock)
                 │  trust anchor  │  identity: IAM OIDC provider + scoped roles
                 └───────┬────────┘
                         │ assume scoped role (OIDC, no static creds)
        ┌────────────────▼─────────────────┐
        │  TOOLBOX CONTAINER / bootstrap VM │  tofu · ansible · kubectl · helm · git
        └───────┬───────────────┬───────────┘
        tofu apply (layers)     ansible (base → security → k3s HA)
                │               │
   AWS infra (VPC, SG, IAM, ECR, 3× m6g) ──> 3-node k3s HA (embedded etcd)
                                                   │ ArgoCD app-of-apps (sync waves)
                                   ┌───────────────┼────────────────┐
                              EBS CSI / gp3   CloudNativePG op.   demo-app
                                              3× PG + PVCs + failover
                                              S3 backups (Barman, instance profile)
                                              ServiceMonitor → Prometheus / Grafana
```

**Flow:** Terraform provisions and scaffolds infrastructure → Ansible configures
nodes and installs Kubernetes → ArgoCD syncs the cluster from git → CloudNativePG
runs an HA Postgres on real persistent volumes with object-store backups → a demo
REST app reads/writes it. The division of labour is deliberate: **Terraform owns
infrastructure, ArgoCD owns in-cluster state, Ansible is the thin bridge** that
turns bare VMs into Kubernetes nodes.

## 2. Framing: why these choices, not just any choices

This platform is built for someone who will **lead a team operating across a
mixed substrate — bare metal, private clouds, and public clouds**,
much of it confidential-computing capable. So the design is biased toward choices
that are **portable, reproducible, and operable by a small team**, over choices
that are merely the fastest path on one provider. That single bias explains most
of what follows — most visibly the Kubernetes distribution.

## 3. Why k3s, not EKS

**Decision: run a self-managed, CNCF-conformant k3s HA cluster (3 servers,
embedded etcd) on EC2, rather than a managed control plane (EKS).** This is the
most consequential choice in the platform, so it gets the most rationale.

### Portability is the whole point
k3s is a single Go binary that installs a fully conformant Kubernetes on
*anything* that runs Linux — bare metal, a private-cloud VM, a public-cloud
instance, or an edge box. The exact same Ansible role that stands the cluster up
here on Graviton EC2 stands it up on a confidential-computing bare-metal host
with no AWS APIs in the loop. **EKS is AWS-only**: its control plane is an AWS
service you cannot lift onto bare metal or a private cloud. For a company whose
substrate is explicitly *not* "always AWS," betting the platform on a control
plane that only exists in one provider is the wrong default.

### Confidential computing wants a control plane you own
Confidential computing means running on hosts (or instance families) where the
*operator* — not the cloud provider — holds the trust boundary. A managed control
plane is, by construction, run by the provider outside that boundary. k3s lets the
control plane itself live on hardware/instances you fully control and can attest,
which is the posture a CC-focused platform ultimately needs. We don't implement
attestation here (it's a documented non-goal), but the choice keeps the door open;
EKS closes it.

### Cost, at PoC scale and at fleet scale
- **EKS** bills **$0.10/hr per cluster control plane (~$73/mo)** *before* any
  worker nodes — and the "operate many small clusters / per-customer or
  per-edge-site clusters" pattern multiplies that.
- **k3s** runs its control plane *on the three EC2 nodes we already pay for* —
  **$0 incremental control-plane cost**. For a PoC, and for the many-small-clusters
  topology a CC company tends toward, k3s is dramatically cheaper.

### It proves the team can operate Kubernetes, not just consume it
Standing up HA embedded-etcd, owning the upgrade cadence, and recovering the
control plane are exactly the skills a team running Kubernetes on owned substrate
needs — and exactly what a managed offering hides. Demonstrating them is a
leadership signal, not incidental.

### Reproducibility
The entire cluster is reproducible from Terraform + Ansible against any Linux
host. EKS ties reproduction to AWS-specific resources (the EKS control plane,
managed node groups, the AWS VPC CNI, IRSA), which is fine until you need to
reproduce it somewhere that isn't AWS.

### Footprint
k3s is batteries-included (containerd, CoreDNS, flannel, local-path, metrics,
and a bundled traefik/servicelb) in one lightweight binary — a good fit for
Graviton and for edge. We disable the bundled traefik so ingress is GitOps-owned;
flannel VXLAN is the default CNI (and the security-group rules are opened for it).

### The vendor angle: managed control planes aren't automatically off the table
A core part of the vendor's value proposition is running **secure/confidential
workloads in public cloud even on managed services** — including, plausibly,
hardening or attesting the control-plane nodes that a managed offering like EKS
operates. In other words, "managed control plane" and "operator-held trust
boundary" are not necessarily mutually exclusive *if* there's a path to securing
the managed nodes. That makes EKS-plus-confidential-hardening a legitimate future
consideration, not a dead end — and worth keeping in view as the product matures.

For **this** project, k3s is still the correct choice for two concrete reasons:

1. **Time/scope.** A self-managed k3s cluster is reproducible end-to-end within
   the timebox; standing up and validating a hardened managed control plane is not.
2. **k3s *is* a likely vendor target in its own right.** A lightweight,
   self-managed, portable distribution running on owned/CC substrate is exactly
   the kind of thing the vendor's software secures — so building on it is aligned
   with the product, not a detour.

### Honest tradeoffs — when EKS *is* the right call
This is a judgement, not dogma. **Pick EKS** when: you are an AWS-only shop with
no portability requirement; you want the provider to own control-plane HA,
patching, and upgrades; you need deep, first-party AWS IAM integration (IRSA) and
AWS support SLAs; you're scaling one very large cluster where managed scaling
earns its keep; or — per the vendor angle above — you have a way to harden/attest
the managed control-plane nodes and want the operational offload anyway. The cost
of k3s is that **we** own control-plane upgrades, patching, and etcd
backup/restore — work EKS would absorb. We accept that cost deliberately because
portability and substrate-independence are the higher-order requirement here.

### Alternatives considered (besides EKS)
| Option | Why not (for this) |
|--------|--------------------|
| **kubeadm** | More moving parts to assemble and maintain; k3s gives the same conformance with far less operational surface. |
| **Talos** | Excellent immutable, API-driven OS — a strong *future* hardening direction (especially for CC). Heavier to adopt in the timebox; noted as a prod-hardening path. |
| **RKE2** | k3s's security-hardened sibling (FIPS, CIS-benchmarked). The natural **"harden k3s for prod / CC"** upgrade path — same operational model, so adopting it later is low-friction. |

This mirrors the repo's consistent thread: **cloud-native for the demo, portable
OSS for production** (ECR → Harbor, AWS OIDC → Ory, cloud-init → Packer, and here
k3s → RKE2/Talos for hardened substrate).

## 4. Key design choices

Each is recorded formally in the [ADR log](#architecture-decision-records-adrs);
this is the at-a-glance summary.

- **Layered Terraform state (Lee-Briggs).** State is split per *rate of change*
  (`10-network` → `15-kms` → `20-security` → `30-iam` → `40-ecr` → `50-compute`),
  per environment, wired with `terraform_remote_state`. Blast radius and plan
  times shrink; `50-compute` can churn between sessions without touching the
  network or the persistent `15-kms` foundation (CMKs + the backup bucket).
  Remote state in S3 with a DynamoDB lock; strict dev/prod separation.
- **Graviton / arm64 end-to-end.** `m6g.large` default. Cost + performance, and
  representative of modern substrate. Forces arm64 across the AMI, k3s, every
  container/Helm image, and the ECR pull-through manifests — handled by design,
  not as an afterthought.
- **Node access via SSM Session Manager (SSH-over-SSM).** No inbound `:22`
  (`20-security` `enable_ssh_ingress=false`); the node role is granted SSM
  (`30-iam` `enable_ssm=true`); Ansible tunnels over a ProxyCommand keyed by the
  EC2 instance-id. IAM-gated and audited; the Terraform-generated SSH key is
  break-glass only. Chosen *over* the Ansible `aws_ssm` connection plugin
  specifically to avoid that plugin's S3 file-transfer bucket — SSH-over-SSM needs
  none. See [`ACCESS.md`](ACCESS.md).
- **Constrained-identity deployment (OIDC, no static creds).** A human admin runs
  only the one-time trust-anchor bootstrap; everything after assumes scoped
  least-privilege roles via federated OIDC (`tofu-plan` read-only, `tofu-apply`,
  …). CI uses its OIDC provider → `AssumeRoleWithWebIdentity`. Native AWS OIDC +
  IAM Identity Center now; **Ory documented** as the portable prod IdP.
- **Customer-managed KMS keys only.** Per-purpose CMKs (state / ECR / EBS), never
  the AWS-managed defaults — for key-policy control, rotation, and grantability
  (a HYOK-friendly posture). ~$1/mo per key.
- **Operator/CI toolbox container + bootstrap VM.** A pinned, supply-chain-verified
  arm64 image (tofu, ansible, kubectl, helm, aws-cli, session-manager-plugin, …)
  is the unit of execution for long ops — it kills toolchain drift across the team
  and decouples long-running applies from an operator's SSO/SSH session timeout.
  Delivered as a container + a cloud-init bootstrap VM; **Packer-baked AMI
  documented** as the immutable prod path.
- **Registry: ECR + pull-through cache** for images and OCI Helm charts; **Harbor**
  documented as the prod recommendation.
- **Storage: EBS CSI + gp3** default StorageClass for real, failover-capable PVCs;
  `local-path` only as a documented descope lever.
- **Backups: CloudNativePG → S3 via Barman Cloud**, authenticated by the **EC2
  instance profile** — no second IAM user. The backup bucket lives in the
  persistent `15-kms` layer (survives compute teardown) and is **SSE-KMS** with a
  customer-managed key. Backup *and* verified restore.
- **GitOps: ArgoCD app-of-apps with sync waves** so operators (CloudNativePG)
  land before the applications that depend on them.
- **Single AWS account for the PoC**, with **account-per-environment /
  account-per-customer (AWS Organizations) documented as the prod model** — the
  cross-account `assume_role` seam is shown in the identity HCL (a `prod` provider
  alias), so promotion is a diff, not a rebuild.

## 5. Cost & lifecycle posture

This is a **PoC: bring up → demo → tear down**, not a standing system. Setup is
~$0 (IAM/OIDC free, state bucket ~$0, CMKs ~$1/mo each). The per-hour meter is
dominated by **3× compute** (`m6g.large` on-demand ≈ $0.27/hr; spot ≈ ~70% less
for iteration) and the **managed NAT gateway** (≈ $0.05/hr + data — the sneaky
always-on). `capacity_type` toggles spot↔on-demand: spot for iteration, on-demand
for the delivery demo.

**Lifecycle discipline:** while iterating, destroy only `50-compute` between
sessions (keep network/security/iam/ecr + identity + state up) to stop the big
meter while keeping fast turnaround. At delivery: same-session up/down plus an
automated reverse-order destroy + cost-leak sweep, with a short KMS deletion
window so retired CMKs stop billing sooner. Realized in [`TEARDOWN.md`](TEARDOWN.md).

## 6. Non-goals & descope levers

**Non-goals:** no confidential-computing implementation (we nod to CC instance
families + attestation in the security narrative only — "works now ⇒ works with
CC"); prod is stubs that prove promotion is a diff, not a second live deployment.

**Descope levers (documented tradeoffs):** compute market (spot ↔ on-demand);
networking (managed NAT → NAT instance → public-subnet/no-NAT); node size
(`m6g.large` → `m6g.medium`); storage (EBS CSI → `local-path`); bootstrap
(cloud-init → Packer); Ory write-up depth.

---

## Architecture Decision Records (ADRs)

Lightweight, append-only. Each records the context, the decision, and its
consequences at the time it was made. Status: `Accepted` unless noted. New
decisions are appended here; superseded ones are marked, not deleted.

### ADR-0001 — Kubernetes distribution: self-managed k3s, not EKS
**Status:** Accepted · **Date:** 2026-06-01
**Context.** The platform must be portable across the vendor's substrate mix (bare
metal / private / public cloud, CC-capable) and reproducible by a small team. A
managed control plane (EKS) is AWS-only and runs outside an operator-held trust
boundary.
**Decision.** Run CNCF-conformant **k3s HA (3 servers, embedded etcd)** on EC2
Graviton nodes, installed by Ansible. Disable bundled traefik (ingress is
GitOps-owned); keep flannel VXLAN as the CNI.
**Consequences.** Full control-plane portability and $0 incremental control-plane
cost; demonstrates real Kubernetes operation. We own control-plane upgrades,
patching, and etcd backup/restore (work EKS would absorb). RKE2/Talos are the
documented hardening path. Full rationale + alternatives: [§3](#3-why-k3s-not-eks).
**Consideration (revisit).** A managed control plane (EKS) is *not* permanently
excluded: the vendor's value proposition includes securing workloads on public-cloud
managed services, plausibly extending to hardening/attesting the managed
control-plane nodes — so "EKS + confidential hardening" is a legitimate future
option to re-evaluate. k3s wins *here* on time/scope and because a lightweight,
self-managed, portable distro on owned/CC substrate is itself a likely vendor
target.

### ADR-0002 — Layered Terraform state (Lee-Briggs), not a single root
**Status:** Accepted · **Date:** 2026-06-01
**Context.** A flat root couples unrelated resources, inflating blast radius and
plan times; `50-compute` churns far more often than the network.
**Decision.** Split state per rate of change (`10-network`…`50-compute`), per
environment, wired with `terraform_remote_state`; remote state in S3 + DynamoDB
lock; strict dev/prod separation.
**Consequences.** Small, fast, low-risk plans; compute can be destroyed between
sessions without touching the network. More wiring (remote-state lookups, apply
ordering) to maintain.

### ADR-0003 — Graviton / arm64 end-to-end
**Status:** Accepted · **Date:** 2026-06-01
**Context.** arm64 offers better price/performance and is representative of modern
substrate.
**Decision.** `m6g.large` default; arm64 enforced across AMI, k3s, all
container/Helm images, and ECR pull-through manifests.
**Consequences.** Lower cost; every image in the supply chain must be arm64 (a
constraint designed for, not patched around).

### ADR-0004 — Node access via SSM SSH-over-SSM, no inbound :22
**Status:** Accepted · **Date:** 2026-06-02
**Context.** Open SSH ingress is attack surface and key-management overhead.
The Ansible `aws_ssm` connection plugin avoids SSH but requires an S3
file-transfer bucket.
**Decision.** Access nodes via SSM Session Manager using an **SSH-over-SSM
ProxyCommand** keyed by instance-id; `20-security` leaves `:22` closed,
`30-iam` grants the node SSM permissions. The TF-generated key is break-glass only.
**Consequences.** No inbound `:22`, IAM-gated + audited access, no transfer
bucket, ordinary Ansible semantics. Depends on the SSM agent + an egress path
(NAT now; VPC interface endpoints documented for a no-egress prod posture).

### ADR-0005 — Constrained-identity deployment via federated OIDC
**Status:** Accepted · **Date:** 2026-06-01
**Context.** Long-lived static credentials are the most common cloud-breach
vector and don't scale to a team + CI.
**Decision.** Admin performs only the one-time trust-anchor bootstrap; all
subsequent runs assume scoped least-privilege roles via OIDC (humans via IAM
Identity Center; CI via `AssumeRoleWithWebIdentity`). Native AWS OIDC now; **Ory**
documented as the portable prod IdP.
**Consequences.** No static deploy creds; auditable, least-privilege automation.
Adds an identity trust-anchor layer to bootstrap and maintain.

### ADR-0006 — Customer-managed KMS keys only
**Status:** Accepted · **Date:** 2026-06-01 (amended 2026-06-04)
**Context.** AWS-managed default keys don't allow key-policy control, custom
rotation, or cross-principal grants — needed for a HYOK-friendly posture.
**Decision.** Per-purpose customer-managed CMKs (state / ECR / EBS / backup);
never the AWS-managed defaults. Each is `enable_key_rotation = true` with a
key policy that delegates use to IAM (root-enable), so consumers are granted in
their IAM role, not the key policy.
**Consequences.** Full key control and grantability; ~$1/mo per key and a
teardown step (CMKs bill until their deletion window closes).
**Resolution of the EBS-CMK churn (2026-06-04).** The EBS CMK used to live in
the `50-compute` layer, so the "destroy only compute between sessions" loop
churned it (orphaned into a pending-deletion window while the next bring-up minted
a fresh one). It now lives — alongside the new backup CMK and the backup bucket —
in a dedicated **persistent `15-kms` foundation layer**, passed into the compute
module via `terraform_remote_state`. Destroying `50-compute` no longer touches the
key, so the deletion window is back to the 30-day default. The state and ECR CMKs
already sat in persistent layers; all CMKs now do. Migration of the existing live
key (state `mv`/import, no re-encrypt) is the procedure in [UPGRADE.md](UPGRADE.md).

### ADR-0007 — Operator/CI toolbox container + cloud-init bootstrap VM
**Status:** Accepted · **Date:** 2026-06-01
**Context.** Toolchain drift across a 3-person team + CI, and SSO/SSH session
timeouts killing long-running applies/upgrades.
**Decision.** A pinned, supply-chain-verified arm64 toolbox image is the unit of
execution; delivered as a container plus a cloud-init bootstrap VM. **Packer AMI**
documented as the immutable prod path. Binaries are vendored + checksum/GPG-verified.
**Consequences.** Reproducible, drift-free, timeout-proof ops; same image runs on
a laptop, a bootstrap host, or as an ArgoCD-triggered Job. An image to build,
version, and keep current (e.g. the aws-cli signing-key expiry).

### ADR-0008 — Registry: ECR + pull-through cache; Harbor for prod
**Status:** Accepted · **Date:** 2026-06-01
**Context.** Need a private registry for images and OCI Helm charts with reliable
upstream caching; want portability off AWS for prod.
**Decision.** ECR with pull-through cache now; **Harbor** documented as the
production recommendation. Upstreams cached: `registry.k8s.io` (credential-free)
plus **quay.io** (ArgoCD images) and **ghcr.io** (CloudNativePG images), each via
a Secrets Manager credential ARN — AWS requires authenticated pull-through for
quay/ghcr/Docker Hub. The node instance profile carries the create-on-pull import
permissions (`ecr:CreateRepository`, `ecr:BatchImportUpstreamImage`), scoped to
the `brzl-dev-*` cache prefixes. The pull-through **credentials must live in
Secrets Manager** — ECR's `credential_arn` cannot reference Parameter Store. The
non-secret **registry host** is published to **SSM Parameter Store**
(`/brzl-dev/ecr/registry_host`) so the bootstrap resolves it on demand (see
ADR-0013), keeping the account id out of git.
**Consequences.** Managed registry with cached upstreams now; a clean OSS
migration target for portable/prod environments. Per-upstream credential secrets
to provision (Secrets Manager, prefix `ecr-pullthroughcache/`); the
account-bearing ECR host is config in Parameter Store, not a committed value.

### ADR-0009 — Storage: EBS CSI + gp3; local-path as descope lever
**Status:** Accepted · **Date:** 2026-06-01
**Context.** The stateful service needs real, failover-capable persistent volumes.
**Decision.** EBS CSI driver + gp3 default StorageClass; `local-path` only as a
documented descope lever if time/cost demands.
**Consequences.** Real PVC failover semantics; EBS volumes are a teardown
cost-leak to sweep (volumes created behind PVCs).

### ADR-0010 — CNPG backups via the EC2 instance profile, no second IAM user
**Status:** Accepted · **Date:** 2026-06-01 (amended 2026-06-04)
**Context.** Object-store backups need S3 credentials; a standing IAM user is a
static-secret liability.
**Decision.** CloudNativePG → S3 via Barman Cloud, authenticated by the **EC2
instance profile** (`barmanObjectStore.s3Credentials.inheritFromIAMRole: true`).
Demonstrate backup *and* restore. The bucket lives in the persistent `15-kms`
layer with **default SSE-KMS** under a customer-managed key; the node role
(`30-iam`) carries scoped S3 read/write **and** `kms:GenerateDataKey`/`Decrypt`
on that one key. The bucket name is account-bearing, so it's published to SSM
(`/brzl-dev/backup/bucket_name`) and reaches the Cluster manifest through a
`__BACKUP_BUCKET__` sentinel resolved at bootstrap (same pattern as the ECR host,
ADR-0013) — no account id in git.
**Consequences.** No long-lived backup credentials; backup auth is tied to node
identity. Backups survive every compute teardown (persistent layer). A bucket
policy rejects any non-SSE-KMS or wrong-key upload, and non-TLS access. (IRSA via
a cluster OIDC issuer is the documented finer-grained future.)

### ADR-0011 — Single AWS account for the PoC; account-per-env/customer for prod
**Status:** Accepted · **Date:** 2026-06-02
**Context.** Real isolation wants separate accounts; building AWS Organizations
now costs time the timebox doesn't have, and reproducibility is the eval criterion.
**Decision.** Single account for the PoC (dev live, prod stub); **account-per-env /
account-per-customer (AWS Organizations) documented as the prod model**, with the
cross-account `assume_role` seam shown in the identity HCL (`prod` provider alias).
**Consequences.** Fast, reproducible PoC; promotion to real isolation is a diff,
not a rebuild. The second account is not actually created.

### ADR-0012 — Managed NAT gateway; spot/on-demand capacity toggle
**Status:** Accepted · **Date:** 2026-06-02
**Context.** Nodes need egress (image pulls, ECR, S3); compute cost dominates the
iteration meter.
**Decision.** A single **managed NAT gateway** (prod-like); a `capacity_type`
toggle (`spot` | `on-demand`) on the compute module — spot for iteration,
on-demand `m6g.large` for the delivery demo.
**Consequences.** Prod-like egress with a documented always-on cost; cheap
iteration via spot, with a real reclaim risk (observed in eu-central-1 — the
toggle let us fall back to on-demand cleanly). NAT-instance / public-subnet are
documented cheaper levers.

### ADR-0013 — GitOps: ArgoCD app-of-apps with sync waves; self-managed
**Status:** Accepted · **Date:** 2026-06-03
**Context.** The cluster config must be declarative, ordered (operators before the
apps that depend on them), and reproducible by the team — not a pile of imperative
`kubectl apply`s. ArgoCD itself needs to be installed before it can manage
anything, and it must read a **private** repo whose image refs point at an
**account-bearing** ECR host.
**Decision.** **ArgoCD** drives the cluster via an **app-of-apps**: one hand-applied
root Application (`gitops/clusters/dev/root.yaml`) watches a flat dir of child
Applications, each tagged with `argocd.argoproj.io/sync-wave` so they reconcile in
order — ArgoCD self-management (wave -1), EBS CSI + gp3 default SC (wave 0), then
operators (CNPG) and applications in later waves. All apps are scoped to an
`brzl-dev` **AppProject**. ArgoCD is **bootstrapped once via Helm**
(`gitops/bootstrap/bootstrap_argocd.sh`, an emit-commands script) and then
**re-adopts its own release** through the wave-(-1) Application, so future ArgoCD
upgrades are git changes. Private-repo reads use a **read-only GitHub deploy key**
held in a gitignored Secret (`.example` committed). Helm charts are fetched from
their upstream repos; only the **container images** are routed through ECR
pull-through (ADR-0008) via committed values.
**Account-id hygiene.** Committed Helm values use a `__ECR_REGISTRY_HOST__`
sentinel rather than the real `<account>.dkr.ecr…` host, so no account id lands in
the delivered repo (consistent with the tfvars/backend hygiene rule). The real
host is published by 40-ecr to **SSM Parameter Store**
(`/brzl-dev/ecr/registry_host`); the bootstrap reads it from there (STS fallback)
and resolves the sentinel via `helm --set` for the one-time install. For the
self-managed Applications it is resolved in git (PoC) — the clean prod resolutions
are an **ApplicationSet cluster generator** (host as a cluster-Secret value, never
in git) or **Harbor**, whose stable hostname carries no account id (reinforcing
ADR-0008's Harbor-for-prod story). *(A brief detour to keep all of this in GitHub
repo Secrets was rejected: GitHub Secrets are write-only outside Actions, and ECR
pull-through can't consume them — so Secrets Manager for creds + Parameter Store
for the host is both required and simpler.)*
**Consequences.** One declarative, ordered, self-healing source of truth; argo
upgrades and app changes are diffs. Adds the bootstrap seam (chicken-and-egg
install), a deploy-key to rotate, and the sentinel/render step for the account-
bearing host until the ApplicationSet/Harbor pattern is adopted.

### ADR-0014 — In-cluster secret projection via External Secrets Operator
**Status:** Accepted · **Date:** 2026-06-04
**Context.** The demo app runs in its own `demo` namespace (team-style separation
from the operator), but its database credential is the CNPG-generated `pg-app`
secret in `cnpg-demo`. Kubernetes Secrets don't cross namespaces, and we won't
copy a credential into git or grant the app broad read access to the operator's
namespace. We also want one coherent, declarative answer to "how are secrets
distributed" for the security story.
**Decision.** **External Secrets Operator** (wave-1 operator, GitOps-installed)
projects the credential. A **least-privilege reader ServiceAccount** in
`cnpg-demo` may `get`/`list`/`watch` only the single `pg-app` secret; a
cluster-scoped **`ClusterSecretStore`** (Kubernetes provider, `remoteNamespace:
cnpg-demo`) authenticates as that SA; an **`ExternalSecret`** in `demo`
materialises `demo/pg-app`. The DSN is **rebuilt via ESO templating** with the
`pg-rw.cnpg-demo.svc.cluster.local` FQDN (CNPG's own `uri` embeds the short
`pg-rw` host, which wouldn't resolve from `demo`) and `sslmode=require`. ESO
images route through ECR pull-through (ghcr upstream, `brzl-dev-github` prefix,
ADR-0008); CRDs are `external-secrets.io/v1beta1` (chart 0.10.7). ESO is
deliberately the same operator that would consume **AWS Secrets Manager** (already
the store for the ECR pull-through credentials, ADR-0008/§secret store), so one
tool spans in-cluster and external secret sources.
**Consequences.** The app keeps its own namespace while **CNPG still owns and
rotates** the credential — ESO's refresh interval picks up rotation. The credential
never lands in git and the app never reaches into `cnpg-demo`. Costs: one more
operator + CRDs to run/upgrade, and a `ClusterSecretStore` + scoped RBAC to
maintain. Prod extension: point ESO at the **AWS Secrets Manager provider** (with
an IRSA-scoped SA) for externally-sourced application secrets.

### ADR-0015 — Local-dev parity via k3d (built)
**Status:** Accepted · **Built:** 2026-06-04 · **Date:** 2026-06-04
**Context.** A developer should be able to run the cluster + app stack on a laptop
for fast inner-loop work without paying the AWS compute/NAT meter. This is
uniquely cheap here: unlike EKS, **the same distribution runs locally** — k3d is
k3s-in-Docker — so local↔cloud parity is high and the GitOps layer (ArgoCD
app-of-apps, CNPG, ESO, demo-app) runs unchanged. We resolved the *design* now but
**deferred the build** to protect the delivery buffer — the required AWS spine and
depth (restore, monitoring, docs, leadership) are sized to the runway, and a local
path is a differentiator, not a TASK requirement.
**Decision.** Local dev targets **k3d** (highest-fidelity k3s mirror). A local
overlay flips exactly three things, all overlay/values changes rather than
refactors, so the manifests stay local-ready by construction:
- **Storage:** gp3 EBS CSI → **`local-path`** (k3d built-in) — already the
  documented descope lever (ADR-0009); CNPG/app `storageClass` is overridable.
- **Image pulls:** **retain ECR** (single source of truth + supply-chain story)
  via a short-lived `aws ecr get-login-password` → imagePullSecret (~12h TTL,
  re-run) or `k3d image import` for the handful of images — there's no instance
  profile on a laptop.
- **Backups:** CNPG → S3 **disabled locally** (`inheritFromIAMRole` needs the EC2
  profile); backup/restore stays an AWS-tested concern (the `barmanObjectStore`
  block is patch-removable).
**Consequences.** A laptop dev loop with real cloud parity, reinforcing the k3s
portability thesis (ADR-0003) — banked now for the architecture + leadership docs.
Build + test of the actual k3d bootstrap (+ a `LOCAL.md` runbook) is deferred to
post-delivery or spare buffer *iff* the AWS spine is already solid; the integration
debugging (ECR-from-local, storage, backup toggle) is deliberately off the delivery
critical path.
**Built (2026-06-04).** Pulled forward once the AWS spine, monitoring, and backups
landed early. Realized as a [`gitops/clusters/local`](../gitops/clusters/local)
kustomize overlay + an emit-commands `k3d_up.sh`, applied directly with `kubectl
apply -k` (not the ECR-coupled ApplicationSet). One design point resolved on
contact: **images use upstream registries + a locally-built `demo-app:local`
(`k3d image import`)**, not the "retain ECR" option — the platform's account-id
host-injection is AWS-specific, so pulling upstream is cleaner and needs no AWS
creds (the ECR-import path is documented in [LOCAL.md](LOCAL.md) as the alternative).
Verified end-to-end first try: CNPG on `local-path`, ESO projection, demo-app search
read/writes the local Postgres — with `AWS_PROFILE` unset. See [LOCAL.md](LOCAL.md).

### ADR-0016 — Account-id-free GitOps: ApplicationSet host injection at render
**Status:** Accepted · **Date:** 2026-06-04
**Context.** Committed GitOps manifests must not contain the AWS account id, yet
in-cluster image pulls go through ECR — and ECR auth (the kubelet credential
provider on the EC2 instance profile, ADR-0008) keys off the **real**
`*.dkr.ecr.*.amazonaws.com` host. A placeholder/mirror host breaks that auth (the
provider can't derive the registry; static `registries.yaml` creds reintroduce the
12 h ECR-token rotation we removed). So the real host **must** appear in the image
refs ArgoCD applies. ArgoCD reconciles a *rendered* desired-state and **self-heal
reverts post-apply edits**, so the host has to enter at **render time**, from a
source ArgoCD reconciles — not a bootstrap `--set` (that only reaches the initial
install) and not committed to git.
**Decision.** A **bootstrap shim** (`resolve_ecr_host.sh`) derives the host from
`aws sts get-caller-identity`; bootstrap writes the host **and** the backup-bucket
name onto the **in-cluster ArgoCD cluster Secret** as annotations
(`brzl.dev/ecr-host`, `brzl.dev/backup-bucket`) — live, never in git. The
app-of-apps is a single **`ApplicationSet`**: a `matrix` of a `clusters` generator
(selector-matched to that Secret, exposing the annotations) × an inline `list` of
the apps. Its `templatePatch` injects the host as **Helm `parameters`** for the
operator charts and as kustomize **`images`** (demo-app) / **`patches`** (CNPG
`imageName` + barman `destinationPath`) for the workloads. Committed manifests keep
the `__ECR_REGISTRY_HOST__` / `__BACKUP_BUCKET__` sentinels purely as documentation;
the rendered output carries the real values. Replaces the prior app-of-apps root +
the PoC sentinel-render escape hatch (the unresolved half of ADR-0013).
**Consequences.** The account id never lands in git and the injection is
self-heal-safe (it's part of desired-state). The bootstrap `--set` still covers
ArgoCD's own image (chicken-and-egg). Costs: one ApplicationSet with a
`templatePatch` (Go-templated, the documented way to express variable Helm params +
per-kind source shapes), an explicitly-registered in-cluster Secret (selector-scoped
so it doesn't duplicate ArgoCD's implicit local cluster), and two `kustomization.yaml`
files so the workloads accept render-time overrides. *Alternatives weighed and
dropped: a private config/ops repo (multi-source `$values`) — clean but a second
repo to run; a CMP `envsubst` sidecar — ideal for plain manifests but mutually
exclusive with native Helm sources, awkward for the operator charts.*
**Validated live (2026-06-04).** Brought up end-to-end: all six apps Synced/Healthy
by wave, host/bucket injection confirmed in the rendered `Application` sources
(Helm params, kustomize images/patches), demo-app read/writes the CNPG HA Postgres.
Two implementation lessons banked: **(1)** in a `matrix`, the `clusters` generator
injects a `name` parameter (the cluster name) that **shadows** any `name` key in the
`list` element — collapsing every app to the cluster's name (duplicate-`Application`
error) and silently disabling `eq .name "…"` branches in the `templatePatch`. Key
list elements on a non-colliding field (`appName`). **(2)** that collision had a
sharp edge: the single mis-named app carried the wave -1 self-manage element, so when
the corrected ApplicationSet **pruned** it, the finalizer cascade-deleted ArgoCD's own
config layer (`argocd-cm`, RBAC, ServiceAccounts) — recovered by re-running the
idempotent `helm upgrade --install` and restarting the controllers for fresh SA tokens
(see [RECOVERY](RECOVERY.md#argocd-control-plane-self-inflicted-prune-)).
**Amendment (2026-07-07).** A pre-publication history audit (gitleaks + a
targeted grep — verifying this ADR's claim rather than trusting it) found the
account id **had** landed in git after all: not in manifests or tfvars (this
ADR's scope, which held), but in three `notes/` run-report/bring-up working
files, present since the repo's initial snapshot commit. Remediated before
publication with a full-history rewrite (`git filter-repo --replace-text`)
substituting documentation placeholders (`123456789012`, `i-0123456789abcdef*`)
for the real account id and the destroyed take-home instance/VPC/SG ids; the
rewrite was re-verified with gitleaks plus an all-blobs grep (zero occurrences).
Lesson: a hygiene claim is scoped to the surfaces it instruments — captured
terminal output in working notes was an uninstrumented channel.

### ADR-0017 — Observability: kube-prometheus-stack, trimmed, port-forward access
**Status:** Accepted · **Date:** 2026-06-04
**Context.** The platform needs system-wide visibility (cluster/node/workload
metrics) plus Postgres metrics, and the demo wants cheap, no-extra-cost web UIs
(Grafana, Prometheus, and the existing ArgoCD panel) — without a billable
LoadBalancer/Ingress.
**Decision.** Add **kube-prometheus-stack** (chart 86.1.1) as a wave-1
GitOps `helm` app in the ApplicationSet: Prometheus + Grafana + node-exporter +
kube-state-metrics + the operator. **Alertmanager is trimmed** (`enabled: false`)
— no notification receiver is wired and it saves resources on the 3-node cluster;
re-enabling is a one-line flip. Prometheus persists its TSDB on gp3 (10Gi, 7d
retention); Grafana on gp3 (2Gi). CNPG Postgres is scraped by enabling the
cluster's **PodMonitor** (`monitoring.enablePodMonitor: true`) and setting the
stack's `*SelectorNilUsesHelmValues: false` so Prometheus discovers monitors
cluster-wide (not just chart-release-labeled ones). The **Postgres dashboard** is
the official CloudNativePG dashboard (grafana.com id 20417), loaded by `gnetId`.
**Access** is **`kubectl port-forward`** via a helper (`gitops/tools/ui_forward.sh`)
that opens Grafana/Prometheus/ArgoCD locally and prints each admin credential —
deliberately no public exposure (the NodePort SG rule is node-to-node only, and a
LoadBalancer would cost). **Image hygiene:** every stack image (≈9, across quay /
registry.k8s.io / ghcr / Docker Hub) routes through ECR pull-through. This needed
the **Docker Hub** pull-through rule (Grafana + the curl dashboard-downloader live
there) — the "monitoring block" analogue of ghcr's "CNPG block" (a Docker Hub
read-only token → Secrets Manager → `40-ecr` `dockerhub_credential_arn`). Account-id
hygiene reuses ADR-0016: a **single `global.imageRegistry`** injection (the new
`hostParams` field on the ApplicationSet element) sets the host once; the
pull-through *prefixes* live in the committed `values.yaml`, so no account id is in
git. Verified offline with `helm template` (all images resolve to
`<host>/brzl-dev-*/…`, zero upstream leaks) before apply.
**Consequences.** Full metrics + dashboards at no incremental AWS cost beyond the
two small gp3 PVCs. The trade-offs: no alerting until Alertmanager is re-enabled
with a receiver; UI access is operator-initiated port-forwarding rather than a
hosted URL (fine for a single-operator PoC; an SSO-fronted Ingress is the
documented prod path).
**App-level metrics.** To make the dashboards show real, continuous activity, the
demo-app was evolved into a small **Sefaria search web app** (search logic borrowed
from the `chofesh` CLI): each query runs a live upstream API call, renders results
in-page, and writes the query + results + a log of the outbound call to Postgres.
It exports Prometheus metrics at `/metrics` (request/search counts + latency,
outbound-call counts + latency, DB rows written) which a **ServiceMonitor** has
Prometheus scrape — so the platform demonstrates app-and-DB observability, not just
infra. (The app makes outbound calls to `www.sefaria.org`; nodes already have NAT
egress, so no SG change is needed.) A custom **app & database overview** dashboard
(generated by `dashboard.gen.py`, shipped as a sidecar ConfigMap) places the
`demoapp_*` and `cnpg_*` series side-by-side with threshold-coloured error/lag
stats, so app↔DB drift is legible at a glance.

### ADR-0018 — Operator SSO gateway (Dex→GitHub), local-first
**Status:** Accepted · **Date:** 2026-06-04
**Scope — optional differentiator, not the core deliverable.** This is an opt-in extra
that lives only under `gitops/clusters/local/sso/` and the `k3d_up.sh --with-sso` flag;
the core platform (and the AWS ApplicationSet) neither installs nor depends on it, and a
reviewer can run/judge the whole CNPG operator + lifecycle story without it. It carries
its **own** pre-staging (a GitHub OAuth App + a FreeDNS credential) kept separate from the
core's image-supply-chain creds (the quay/ghcr/Docker-Hub ECR pull-through tokens). Built
+ proven end-to-end on local k3d (browser tiers + trusted LE-prod cert + kube-API OIDC).
**Context.** ADR-0017 left UI access as per-service `kubectl port-forward` with each
tool's own admin+password — fine for one operator, but the wrong security posture to
demonstrate: independent local logins, no central revocation, no role tiers, and
nothing tying cluster-UI access to the cluster API. We want **one** GitHub-backed
sign-on in front of the operator web UIs *and* the kube-API, with tiers, built where
there's no billing meter (the k3d local cluster — ADR-0015) and **portable to AWS**.
**Decision.** A self-hosted OIDC edge, all upstream images, no AWS dependency:
- **Dex** is the single OIDC issuer (`https://dex.sso.barzel.sh`), federating a
  **GitHub OAuth App** as the human IdP and re-issuing a uniform identity.
- **Three per-host `oauth2-proxy` instances** in full **reverse-proxy** mode (not
  Traefik forward-auth — which 401s without redirecting). Each TLS host
  (`grafana`/`prometheus`/`demo`.sso.barzel.sh) routes through its proxy, which does
  the native 401→Dex→callback→cookie→upstream dance. **Tiers** are enforced at the
  proxy: `grafana`+`prometheus` require an **operator email allowlist**; `demo` allows
  any authenticated GitHub user (the low `users` tier). Grafana additionally trusts the
  proxy's `X-Auth-Request-Email` via `auth.proxy` with its local login form **off**.
- **TLS** is a real **Let's Encrypt wildcard** `*.sso.barzel.sh` from **cert-manager**
  solving **DNS-01** through the **FreeDNS (afraid.org) webhook** — the operator owns
  `barzel.sh`, so this is the *same* cert-manager/DNS-01 path AWS will use (only the A
  records differ), with no browser warnings and no host needing to be internet-reachable.
- **kube-API OIDC**: the k3s API server is started with `--oidc-issuer-url` = the same
  Dex, so `kubectl` via **oidc-login (kubelogin)** authenticates by the same GitHub
  identity; RBAC binds the operator. Traefik (k3s built-in) is the HTTPS edge — no
  Ingress install — and every IngressRoute, its TLS secret, and its proxy backend live
  in `sso`, so no cross-namespace Traefik flag is needed.
**Personal-vs-org identity.** The demo uses a *personal* GitHub account (no org), so
Dex emits **no group claims** — tiers are therefore keyed on the **operator email**
(`OPERATOR_EMAIL`, = the GitHub primary email) at the oauth2-proxy allowlist and the
kube-RBAC subject. With a GitHub **org**, the connector gains `orgs:`/`teams:`, the
tiers become group claims (`oidc:brzl-admins`/`-operators`/`-users`), and only the
subject *kind/name* in the allowlist + RBAC change — the topology is identical.
**k3d reachability wrinkle.** The browser and the in-container kube-API server must
resolve `dex.sso.barzel.sh` to the *same* Dex. The browser uses `/etc/hosts`→127.0.0.1
(k3d maps host :443→Traefik); the API server is given the k3d **serverlb** container IP
for that host via a post-create `/etc/hosts` entry on the server node. oauth2-proxy
sidesteps DNS entirely: it skips OIDC discovery and reads token/JWKS over in-cluster
Service DNS while keeping the public issuer for `iss` validation. (Fallback if the
FreeDNS webhook fights: SelfSigned issuer over `sslip.io` + an API-server `oidc-ca-file`
— a one-issuer swap; the web-UI gate is otherwise unchanged.)
**Consequences.** One sign-on, central revocation (revoke at GitHub or flip the
allowlist), real role tiers, and the cluster UIs + API share an identity — at zero AWS
cost. Trade-offs: more moving parts (Dex + three proxies + cert-manager + a third-party
DNS-01 webhook, which is pinned and reviewed); LE **staging** is used while validating
DNS-01 (browser-distrusted + kube-API can't trust it → flip to **prod** for the clean
demo); and the secrets (GitHub OAuth client, the Dex↔proxy client+cookie, the FreeDNS
cred) are bootstrap-injected as env, never in git (`create_sso_secrets.sh`, [SECRETS.md](SECRETS.md)).
**Promote to AWS:** the Dex/oauth2-proxy/cert-manager manifests are unchanged; only
point `*.sso.barzel.sh` A records at the Terraform NLB (afraid.org stays the DNS, or
delegate to Route53) and add the API-server OIDC flag to the Ansible `kubernetes` role.
**Authored 2026-06-04; live bring-up pending** the operator's GitHub OAuth App + FreeDNS
credential + `/etc/hosts` (see [LOCAL.md](LOCAL.md) `--with-sso`, [ACCESS.md](ACCESS.md)).

### ADR-0019 — Prod environment: private-subnet placement, NLB-only ingress
**Status:** Accepted · **Date:** 2026-06-10 · **Validated live 2026-06-10** · **Layout superseded in part by [ADR-0020]** — the *per-env-directory* form below (`terraform/environments/prod/`) is retired; the placement / NLB / tunnel *decisions* stand, now expressed as model-B inputs (`public_nodes=false`, `enable_public_ingress=true`) on the single-source stack. (7/7
apps Synced/Healthy on private nodes, demo-app served through the NLB).
**Context.** Dev placed nodes in public subnets (admin-/32-locked) for direct
operability. Environment separation wants prod to be the same modules
with the production posture: no public node surface at all.
**Decision.** `terraform/environments/prod/` composes the same modules with
private-subnet placement: no public IPs (`associate_public_ip_address=false`),
egress via NAT, node access unchanged over SSM (the agent's channel is outbound).
The kube-API is reached through a **driver-managed SSM port-forward**
(`gitops/tools/api_tunnel.sh`, invoked by every kubectl-using `platform.sh` phase;
kubeconfig server `https://127.0.0.1:6443` — in k3s's default TLS SANs, so cert
validation holds through the tunnel). The **only public surface is a
Terraform-owned NLB** fronting the demo-app UI: self-managed k3s has no AWS
cloud-controller, so a `Service` of type LoadBalancer would pend forever — the
NLB (prod `50-compute/ingress.tf`) targets a fixed NodePort (30080, patched onto
the demo-app Service by the prod ApplicationSet), with the node SG admitting that
port from the NLB's SG only and the NLB listener allowlisted to the operator /32
(`lb_ingress_cidr` widens it deliberately). Monitoring runs in prod via
**`values-prod.yaml`** — kube-prometheus-stack is the one chart whose committed
values carry the env-scoped pull-through prefixes, so each env gets a values file
kept in lockstep modulo prefix.
**Consequences.** The prod placement model is built and proven, not asserted;
promotion really is composition (same modules, different inputs). Costs: the NLB
(~$0.02/hr, in the churned compute layer on purpose) and the tunnel as an
operational dependency — owned by the driver, not operator memory.
**Known limitation (designed fix, post-delivery).** The ApplicationSet itself
sits *above* the GitOps line: applied at bootstrap, updated by `kubectl apply`,
not reconciled from git — the 2026-06-10 bring-up felt this three times. The fix
is the standard root-app pattern: a wave -1 cluster-config Application syncing
`gitops/clusters/<env>/` with an `include` for `applicationset.yaml` +
`project.yaml` only — `in-cluster.yaml` stays excluded because its live
host/bucket annotations are deliberately not in git (ADR-0016) and self-heal
would strip them. Related: the dev/prod ApplicationSets are largely duplicated
(a `hostParams` omission in the prod copy cost one live debug cycle); diff-review
them as a pair until they're generated from one source.

### ADR-0020 — Single-source environment stack (model B) + driver-composed state backend
**Status:** Accepted · **Date:** 2026-06-17 · **Offline-validated** (all six layers
`tofu validate`-clean; driver wired) · **live validation pending** (greenfield — nothing
deployed). Supersedes ADR-0019's per-env-directory *layout*.
**Context.** dev and prod were near-duplicate per-env trees (`terraform/environments/{dev,prod}/<layer>`),
~90% identical. Hand-maintained copies *drift* — the 2026-06-10 ApplicationSet
`hostParams` omission (ADR-0019) cost a live debug cycle. But the dev→prod **promotion
gate** is *separate environment instances* — distinct state + independent apply — which
is **orthogonal to source layout**; duplicated source was protecting the wrong thing.
**Decision.** One source per layer under **`terraform/stack/aws/<layer>/`**, applied per
environment via a committed per-env **`<env>.tfvars`** (`-var-file`). State: **one S3
bucket + one CMK, environments split by the object key** `<env>/<layer>/terraform.tfstate`;
each layer's `backend "s3" {}` is empty and the driver (`platform.sh`) **composes** it at
`init -reconfigure` (bucket derived from the caller's account, key from `ENV`+layer) — no
per-env `backend.hcl`. Cross-layer `terraform_remote_state` derives the bucket the same
way and keys lower layers by `var.env`. **Intentional** per-env differences are explicit
*inputs*, not forks: 40-ecr's dev-only toolbox build (`repositories` + `toolbox_build_enabled`),
50-compute placement (`public_nodes`) and the demo-app NLB (`enable_public_ingress`,
count-gated — prod on, dev off, flag-flip to adopt). Committed `<env>.tfvars` hold only
non-secret defs; rendered secret/ARN tfvars use gitignored `*.auto.tfvars`. The conductor
+ `bootstrap`/`identity` stay account-primitives (own `backend.hcl`), not stack layers.
**Consequences.** Drift is structurally removed (one source; the per-env diff is two small
tfvars). Forward-compatible with multi-account (per-account buckets, conductor tied to its
account's state — SPEC §9). Tradeoff: a shared layer dir means `init -reconfigure` per env
switch (the driver does it), and "has prod's code caught up to dev's?" becomes a git-ref
question rather than a directory diff. Full detail: **SPEC §3** (model B + state backend),
**§9** (multi-account direction). Rejected: workspaces (weak state isolation, fights
multi-account, switch-footgun); keeping per-env dirs (the drift source).
