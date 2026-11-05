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

barzel-cluster is a **platform**: a general, secured Kubernetes cluster that
runs on several **substrates** (k3d on a laptop, AWS, and later GCP or
DigitalOcean) with as few changes as possible. It is the backbone of a CI/CD
chain, and it does not depend on any workload. An **example app** shows that
it runs stateless and stateful workloads; any other app can take its place.

The platform moves changes along a chain of environments, from local to a
shared remote environment to production. The local environment is the first
step, and it has the same shape as the others:

```text
 driver (kiesei, outside the cluster)
   │  phases: 10-substrate → 20-images → 25-bootstrap → 30-gitops → 40-workloads
   │  each phase: emit a run sheet → run it → check it
   ▼
 services outside the cluster          the cluster
 (exist before it, outlive it)         ┌────────────────────────────────────┐
 ┌──────────────────────────┐          │ conductor (kiesei, warm pod)       │
 │ registry       (Zot)     │◀─pull────│ Argo CD + one platform ApplicationSet
 │ secret store   (OpenBao) │◀─ESO─────│ ESO, CNPG operator, workloads      │
 │   (also the local CA)    │◀─sign────│ cert-manager                       │
 │ DNS stand-in   (CoreDNS) │          │ admin portal: nginx, one host name │
 │ admin log store data     │◀─logs────│ log collector, two Loki stores     │
 │ log collector: the run   │──OTLP───▶│ Prometheus, Grafana                │
 │   outputs, store audit   │          │                                    │
 └──────────────────────────┘          └────────────────────────────────────┘
```

On a cloud, each local stand-in becomes the cloud's own service: the
registry, the secret store, public DNS and a public CA, and object storage.
The **substrate adapter** for each cloud gives the same outputs to the same
phases. The local environment therefore needs nothing public to run, and
still has the shape of a production environment (ADR-0036).

**Flow: how a change reaches a cluster.** Two kinds of change travel two
separate roads, and Argo CD in each cluster is where they meet:

```text
  barzel-cluster (this repo)               a workload's repo (chofesh: private,
  the platform: ApplicationSet +           under a GitHub organization)
  manifests                                manifests (deploy/) + source + its CI
         │ push a branch                          │ push to main  ─▶ CI: image :<commit>
         │                                        │ tag vX.Y.Z    ─▶ CI: image :vX.Y.Z
         ▼                                        ▼ ghcr.io, a private package
  ┌─ local ───────────────────────────┐    ┌─────────────────────────────────┐
  │ Argo CD follows the branch the    │◀───│ registry: Zot / ECR, a pull-    │
  │ driver checked out                │    │ through with the packages token │
  │ (break-glass open: a source tree) │    └─────────────────────────────────┘
  │ workload: follow = branch         │    reads of the repo: a GitHub App,
  │  the SCM generator asks GitHub    │    read-only, one per organization
  │  for the head of main every 5 min │    (Argo CD and the SCM generator)
  │  ─▶ manifests at that commit,     │
  │     image :<commit>               │
  └───────────────┬───────────────────┘
                  │ promote platform (pass 7): the platform revision,
                  ▼ one environment at a time
  ┌─ dev ────────────┐      ┌─ prod ───────────┐   workload: follow = release
  │ revision = A     │ ───▶ │ revision = A     │   the element names the tag;
  │ release vX.Y.Z   │      │ release vX.Y.Z   │   the manifests at the tag name
  └──────────────────┘      └──────────────────┘   the image :vX.Y.Z
                  promote workloads (pass 9): the release, one environment
                  at a time, from the workload's own CI
```

A **platform change** is a commit here. Argo CD renders the one platform
ApplicationSet (ADR-0025) from the revision named in the cluster's
registration. Local follows the branch the driver checked out (GitOps mode)
or applies the working tree while the break-glass is open (`break-glass
apply`, ADR-0025 amendment, ADR-0038). `promote platform` moves that
revision to the next environment. A **workload change**
is a commit in the workload's repo, and nothing else. Its CI publishes the
image, and the environment's **follow policy** (ADR-0034) decides what Argo
CD deploys. Local follows the development branch. An SCM generator in the
ApplicationSet gives the head commit. Argo CD reads the manifests at that
commit and the image CI published for it. The page shows the change
about eight minutes after the push. The other environments follow a release
tag, which `promote workloads` moves along the chain (pass 9). The driver
never builds or touches a workload. In both cases Argo CD, not an operator,
applies the change. Break-glass mode is the recorded exception
([BREAK-GLASS.md](BREAK-GLASS.md), ADR-0037).

**Adding a workload.** The platform does not know its workloads. A new one
is a contract on its own side and one element on the platform's side.

- *The workload's repo* has a `deploy/` directory with a Kustomize base and
  one overlay per kind of environment (`local`, `aws`). `main` is the
  development branch. Its CI publishes the image under the commit's first
  8 hex digits and the moving tag `main`. A release is a tag `vX.Y.Z`, and
  the manifests at that tag name the image `:vX.Y.Z`. The manifests name
  images as published, never a platform's registry. A page behind the admin
  portal has relative links only. A database is the workload's own, through
  the CNPG operator. Secrets from outside the cluster come through the
  cluster secret store (ADR-0026). chofesh's `make release` and `make
  dev-image` are the reference.
- *The platform* gets one element in the ApplicationSet, with `repo`,
  `revision` (the release), `path` and `localPath`. The element sits in a
  matrix with the SCM generator for the workload's organization. The repo goes into each
  AppProject's `sourceRepos`, and the workload gets a location in the admin
  portal. The ApplicationSet renames the registry host, never a tag.
- *A public repo with a public package* needs nothing more.
- *A private repo and package* is the reference case. The repo is under a
  GitHub **organization**, because the SCM generator lists an
  organization's repositories. A GitHub App on that organization, read-only
  (contents, metadata), serves Argo CD as `repo-creds` for the organization
  and serves the SCM generator. A classic token with only `read:packages`
  serves the registry's pull-through, since the container registry accepts
  no other kind. `driver/access/github.sh` makes both with the operator's
  `gh` login, in six steps ([INSTALL.md](INSTALL.md), section 4). Phase 25
  seeds them into the store once. An App can also read a private repo under
  a personal account, but the generator cannot list a user's repositories.
  Such a workload follows releases only.

**Division of labour:** OpenTofu owns the infrastructure, Argo CD owns the
state in the cluster, and the driver sequences the phases that connect them.
Ansible is the thin bridge that turns bare VMs into Kubernetes nodes where a
substrate needs it.

## 2. Framing: why these choices

The platform must be **portable, reproducible and operable by a small team**,
and **simple**: the plainest working shape wins over the fastest path on one
provider. Three rules follow from this, and they explain most of what follows:

- **Local first.** Every change runs on the local environment before it goes
  further. Local mimics the cloud: a service that is outside the cluster on a
  cloud is also outside the cluster on local (ADR-0023, ADR-0026).
- **One interface for each substrate.** The platform layer assumes only
  conformant Kubernetes plus the adapter's outputs (SPEC §3).
- **The platform does not know its workloads.** Workloads bring their own
  manifests, secrets and databases; the platform gives them capabilities.

**Confidential computing as a guide.** The project started on a design brief
for a confidential-computing company. Confidential computing is no longer the
goal, but support for it stays a useful test: a platform that can run with an
operator-held trust boundary, on owned or attested hosts, is a platform that
does not depend on one provider. This is one reason for a self-managed
control plane (§3).

## 3. Why k3s, not a managed control plane

**Decision: run a self-managed, CNCF-conformant k3s cluster on each
substrate, not a managed control plane such as EKS** (ADR-0001). The SPEC §3
portability rule keeps the option open to replace k3s with a managed control
plane inside one substrate adapter later.

### Portability

k3s is a single binary that installs conformant Kubernetes on any Linux host:
bare metal, a private-cloud VM, a public-cloud instance, or a container on a
laptop (k3d). The same installation works on every substrate. A managed
control plane exists only in its provider.

### An operator-held trust boundary

With k3s, the control plane runs on hosts that the operator controls and can
attest. A managed control plane runs outside that boundary. The platform does
not implement attestation, but this choice keeps it possible.

### Cost, for one cluster and for many

- **EKS** bills **$0.10/hr per cluster control plane (~$73/mo)** *before* any
  worker nodes — and the "operate many small clusters / per-customer or
  per-edge-site clusters" pattern multiplies that.
- **k3s** runs its control plane *on the nodes we already pay for* —
  **$0 incremental control-plane cost**. For the many-small-clusters topology,
  k3s is much cheaper.

### It proves the team can operate Kubernetes, not just consume it

Standing up HA embedded-etcd, owning the upgrade cadence, and recovering the
control plane are exactly the skills a team running Kubernetes on owned substrate
needs — and exactly what a managed offering hides.

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

### Honest tradeoffs — when EKS *is* the right call

This is a judgement, not dogma. **Pick EKS** when: you are an AWS-only shop with
no portability requirement; you want the provider to own control-plane HA,
patching, and upgrades; you need deep, first-party AWS IAM integration (IRSA) and
AWS support SLAs; you're scaling one very large cluster where managed scaling
earns its keep. The cost of k3s is that **we** own control-plane upgrades,
patching, and etcd backup/restore — work EKS would absorb. We accept that
cost deliberately, because portability and substrate-independence are the
higher-order requirement here.

### Alternatives considered (besides EKS)

| Option | Why not (for this) |
| -------- | -------------------- |
| **kubeadm** | More moving parts to assemble and maintain; k3s gives the same conformance with far less operational surface. |
| **Talos** | Excellent immutable, API-driven OS — a strong *future* hardening direction. Heavier to adopt; noted as a prod-hardening path. |
| **RKE2** | k3s's security-hardened sibling (FIPS, CIS-benchmarked). The natural **"harden k3s for prod"** upgrade path — same operational model, so adopting it later is low-friction. |

This mirrors the repo's consistent thread: **cloud-native where it is the
simplest path, portable OSS where portability matters** (ECR → Harbor, AWS
OIDC → Ory, cloud-init → Packer, and here k3s → RKE2/Talos for a hardened
substrate).

## 4. Key design choices on the AWS substrate (as built, June 2026)

These choices describe the AWS substrate as it was built and verified in June
2026. Pass 8 (BACKLOG) turns it into the AWS substrate adapter; some choices
change then. Each is recorded formally in the [ADR index](#architecture-decision-records-adrs);
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
- **Operator/CI kiesei container + bootstrap VM.** A pinned, supply-chain-verified
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
  persistent `15-kms` layer (survives compute teardown) and is **SSE-KMS**
  with a customer-managed key. Backup *and* verified restore.
- **GitOps: ArgoCD app-of-apps with sync waves** so operators (CloudNativePG)
  land before the applications that depend on them.
- **Single AWS account for the PoC**, with **account-per-environment /
  account-per-customer (AWS Organizations) documented as the prod model** — the
  cross-account `assume_role` seam is shown in the identity HCL (a `prod` provider
  alias), so promotion is a diff, not a rebuild.

## 5. Cost & lifecycle posture (AWS)

On AWS, an environment is brought up, used and torn down; it is not a
standing system. Setup is
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

**Non-goals:** no confidential-computing implementation (attestation and CC
instance families stay a guide, §2); no dependency on any one workload.

**Descope levers (documented tradeoffs):** compute market (spot ↔ on-demand);
networking (managed NAT → NAT instance → public-subnet/no-NAT); node size
(`m6g.large` → `m6g.medium`); storage (EBS CSI → `local-path`); bootstrap
(cloud-init → Packer); Ory write-up depth.

---

## Architecture Decision Records (ADRs)

One file for each ADR in [`adr/`](adr/). Each records the context, the
decision, and its consequences at the time it was made. ADRs are
append-only: a superseded ADR is marked, not deleted.

| ADR | Decision | Status |
| ----- | ---------- | -------- |
| [ADR-0001](adr/0001-kubernetes-distribution-self-managed-k3s-not-eks.md) | Kubernetes distribution: self-managed k3s, not EKS | Partly superseded by ADR-0030 |
| [ADR-0002](adr/0002-layered-terraform-state-lee-briggs-not-a-single.md) | Layered Terraform state (Lee-Briggs), not a single root | Partly superseded by ADR-0020 |
| [ADR-0003](adr/0003-graviton-arm64-end-to-end.md) | Graviton / arm64 end-to-end | Accepted |
| [ADR-0004](adr/0004-node-access-via-ssm-ssh-over-ssm-no-inbound-22.md) | Node access via SSM SSH-over-SSM, no inbound :22 | Accepted |
| [ADR-0005](adr/0005-constrained-identity-deployment-via-federated-oidc.md) | Constrained-identity deployment via federated OIDC | Accepted |
| [ADR-0006](adr/0006-customer-managed-kms-keys-only.md) | Customer-managed KMS keys only | Accepted |
| [ADR-0007](adr/0007-operator-ci-toolbox-container-cloud-init-bootstrap.md) | Operator/CI toolbox container + cloud-init bootstrap VM | Superseded by ADR-0021 |
| [ADR-0008](adr/0008-registry-ecr-pull-through-cache-harbor-for-prod.md) | Registry: ECR + pull-through cache; Harbor for prod | Partly superseded by ADR-0016, ADR-0023, ADR-0025 |
| [ADR-0009](adr/0009-storage-ebs-csi-gp3-local-path-as-descope-lever.md) | Storage: EBS CSI + gp3; local-path as descope lever | Accepted |
| [ADR-0010](adr/0010-cnpg-backups-via-the-ec2-instance-profile-no.md) | CNPG backups via the EC2 instance profile, no second IAM user | Partly superseded by ADR-0016, ADR-0025 |
| [ADR-0011](adr/0011-single-aws-account-for-the-poc-account-per-env.md) | Single AWS account for the PoC; account-per-env/customer for prod | Accepted |
| [ADR-0012](adr/0012-managed-nat-gateway-spot-on-demand-capacity-toggle.md) | Managed NAT gateway; spot/on-demand capacity toggle | Accepted |
| [ADR-0013](adr/0013-gitops-argocd-app-of-apps-with-sync-waves-self.md) | GitOps: ArgoCD app-of-apps with sync waves; self-managed | Split: ADR-0031, ADR-0016, ADR-0032 |
| [ADR-0014](adr/0014-in-cluster-secret-projection-via-external-secrets.md) | In-cluster secret projection via External Secrets Operator | Superseded by ADR-0034 (pass 5d): the projection went with the demo-app |
| [ADR-0015](adr/0015-local-dev-parity-via-k3d-built.md) | Local-dev parity via k3d (built) | Superseded by ADR-0024 |
| [ADR-0016](adr/0016-account-id-free-gitops-applicationset-host.md) | Account-id-free GitOps: ApplicationSet host injection at render | Partly superseded by ADR-0025 |
| [ADR-0017](adr/0017-observability-kube-prometheus-stack-trimmed-port.md) | Observability: kube-prometheus-stack, trimmed, port-forward access | Split: ADR-0033, ADR-0028, ADR-0034 |
| [ADR-0018](adr/0018-operator-sso-gateway-dex-github-local-first.md) | Operator SSO gateway (Dex→GitHub), local-first | Split: ADR-0035, ADR-0028 |
| [ADR-0019](adr/0019-prod-environment-private-subnet-placement-nlb-only.md) | Prod environment: private-subnet placement, NLB-only ingress | Layout superseded in part by ADR-0020 |
| [ADR-0020](adr/0020-single-source-environment-stack-model-b-driver.md) | Single-source environment stack (model B) + driver-composed state backend | Accepted |
| [ADR-0021](adr/0021-kiesei-driver-and-conductor.md) | Kiesei: one operator image, driver and conductor modes | Accepted |
| [ADR-0022](adr/0022-driver-runs-phases-through-run-logs.md) | The driver runs phases through run-logs (now: run sheets) | Accepted; adapter interface → ADR-0030 |
| [ADR-0023](adr/0023-mimic-cloud-services-locally.md) | Mimic cloud services locally now; decide on portable services later | Partly superseded by ADR-0026 |
| [ADR-0024](adr/0024-local-is-the-first-environment.md) | Local is the first environment in the promotion chain | Accepted; k3s line → ADR-0030 |
| [ADR-0025](adr/0025-one-platform-applicationset-cluster-secret-values.md) | One platform ApplicationSet; values and sync switch per cluster | Accepted; amended item 13 (`apply` on `argocd app sync --local`); the sync verbs went into break-glass mode in item 37 (ADR-0038) |
| [ADR-0026](adr/0026-local-secret-store-outside-the-cluster.md) | The local cluster secret store runs outside the cluster | Accepted |
| [ADR-0027](adr/0027-logs-admin-and-diagnostic-stores.md) | Logs: an admin log store and a diagnostic log store | Accepted; amended Q158–Q162, Q163–Q166 (mutual TLS on the OTLP receiver) and Q210–Q217 (the cold log store on local); built in pass 6, item 4a and pass 6c |
| [ADR-0028](adr/0028-admin-portal.md) | The admin portal: one nginx, a static page, a path for each service | Accepted; built in pass 5c; amended Q177 (sign-on in every environment) |
| [ADR-0029](adr/0029-vendored-doctrine-helpers-pinned.md) | The Bash doctrine helpers are vendored, pinned to a tagged commit | Accepted |
| [ADR-0030](adr/0030-substrate-adapter-interface.md) | One substrate adapter interface; the platform layer assumes only conformant Kubernetes | Accepted |
| [ADR-0031](adr/0031-argocd-manages-itself.md) | Argo CD manages itself (from ADR-0013) | Accepted |
| [ADR-0032](adr/0032-argocd-repository-credential.md) | The Argo CD repository credential: deploy key now, GitHub App before leaving local (from ADR-0013) | Accepted; to be superseded in pass 8 |
| [ADR-0033](adr/0033-metrics-kube-prometheus-stack.md) | Metrics: kube-prometheus-stack, trimmed (from ADR-0017) | Accepted (AWS substrate) |
| [ADR-0034](adr/0034-example-app-is-a-separate-workload.md) | The example app is a separate workload (chofesh, private, from its own repo and CI); an environment follows a branch or a release; the platform depends on no workload | Accepted; built (pass 5d) |
| [ADR-0035](adr/0035-operator-sign-on-dex-oauth2-proxy.md) | Operator sign-on: Dex → GitHub, oauth2-proxy, kube-API OIDC (from ADR-0018) | Accepted; amended Q169–Q183; steps 1 (web sign-on) and 2 (`kubectl` through Dex) built in pass 6a |
| [ADR-0036](adr/0036-cert-manager-and-local-stand-ins-for-public-services.md) | cert-manager renews the portal's certificate; local stand-ins for public DNS and a public CA | Accepted (pass 5c) |
| [ADR-0037](adr/0037-break-glass-mode.md) | Break-glass mode: `open` stops sync and elevates the admins, with a record; `close` gives the cluster back to git; the reader of the admin log store | Accepted (pass 6b, Q195–Q209); built; the verbs renamed in item 37 (ADR-0038) |
| [ADR-0038](adr/0038-driver-grammar.md) | The driver grammar: `BRZL_ENV=<env> driver.sh <mode> <verb>`; the modes `cluster`, `break-glass`, `audit`; the sync verbs fold into break-glass; the teardown guard | Accepted (item 37, Q234–Q243); built |
