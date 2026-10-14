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
   │  each phase: emit a run-log → run it → check it
   ▼
 services outside the cluster          the cluster
 (exist before it, outlive it)         ┌────────────────────────────────────┐
 ┌──────────────────────────┐          │ conductor (kiesei, warm pod)       │
 │ registry       (Zot)     │◀─pull────│ Argo CD + one platform ApplicationSet
 │ secret store   (OpenBao) │◀─ESO─────│ ESO, CNPG operator, workloads      │
 │ admin log store data     │◀─logs────│ log collector, Grafana  (pass 6)   │
 └──────────────────────────┘          │ admin portal: nginx    (pass 5c)   │
                                       └────────────────────────────────────┘
```

On a cloud, each local stand-in becomes the cloud's own service: the
registry, the secret store and object storage. The **substrate adapter** for
each cloud gives the same outputs to the same phases.

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
| [ADR-0001](adr/0001-kubernetes-distribution-self-managed-k3s-not-eks.md) | Kubernetes distribution: self-managed k3s, not EKS | Accepted |
| [ADR-0002](adr/0002-layered-terraform-state-lee-briggs-not-a-single.md) | Layered Terraform state (Lee-Briggs), not a single root | Accepted |
| [ADR-0003](adr/0003-graviton-arm64-end-to-end.md) | Graviton / arm64 end-to-end | Accepted |
| [ADR-0004](adr/0004-node-access-via-ssm-ssh-over-ssm-no-inbound-22.md) | Node access via SSM SSH-over-SSM, no inbound :22 | Accepted |
| [ADR-0005](adr/0005-constrained-identity-deployment-via-federated-oidc.md) | Constrained-identity deployment via federated OIDC | Accepted |
| [ADR-0006](adr/0006-customer-managed-kms-keys-only.md) | Customer-managed KMS keys only | Accepted |
| [ADR-0007](adr/0007-operator-ci-toolbox-container-cloud-init-bootstrap.md) | Operator/CI toolbox container + cloud-init bootstrap VM | Superseded by ADR-0021 |
| [ADR-0008](adr/0008-registry-ecr-pull-through-cache-harbor-for-prod.md) | Registry: ECR + pull-through cache; Harbor for prod | Accepted |
| [ADR-0009](adr/0009-storage-ebs-csi-gp3-local-path-as-descope-lever.md) | Storage: EBS CSI + gp3; local-path as descope lever | Accepted |
| [ADR-0010](adr/0010-cnpg-backups-via-the-ec2-instance-profile-no.md) | CNPG backups via the EC2 instance profile, no second IAM user | Accepted |
| [ADR-0011](adr/0011-single-aws-account-for-the-poc-account-per-env.md) | Single AWS account for the PoC; account-per-env/customer for prod | Accepted |
| [ADR-0012](adr/0012-managed-nat-gateway-spot-on-demand-capacity-toggle.md) | Managed NAT gateway; spot/on-demand capacity toggle | Accepted |
| [ADR-0013](adr/0013-gitops-argocd-app-of-apps-with-sync-waves-self.md) | GitOps: ArgoCD app-of-apps with sync waves; self-managed | Accepted |
| [ADR-0014](adr/0014-in-cluster-secret-projection-via-external-secrets.md) | In-cluster secret projection via External Secrets Operator | Accepted |
| [ADR-0015](adr/0015-local-dev-parity-via-k3d-built.md) | Local-dev parity via k3d (built) | Superseded by ADR-0024 |
| [ADR-0016](adr/0016-account-id-free-gitops-applicationset-host.md) | Account-id-free GitOps: ApplicationSet host injection at render | Accepted |
| [ADR-0017](adr/0017-observability-kube-prometheus-stack-trimmed-port.md) | Observability: kube-prometheus-stack, trimmed, port-forward access | Accepted |
| [ADR-0018](adr/0018-operator-sso-gateway-dex-github-local-first.md) | Operator SSO gateway (Dex→GitHub), local-first | Accepted |
| [ADR-0019](adr/0019-prod-environment-private-subnet-placement-nlb-only.md) | Prod environment: private-subnet placement, NLB-only ingress | Accepted |
| [ADR-0020](adr/0020-single-source-environment-stack-model-b-driver.md) | Single-source environment stack (model B) + driver-composed state backend | Accepted |
| [ADR-0021](adr/0021-kiesei-driver-and-conductor.md) | Kiesei: one operator image, driver and conductor modes | Accepted |
| [ADR-0022](adr/0022-driver-runs-phases-through-run-logs.md) | The driver runs phases through run-logs | Accepted |
| [ADR-0023](adr/0023-mimic-cloud-services-locally.md) | Mimic cloud services locally now; decide on portable services later | Accepted |
| [ADR-0024](adr/0024-local-is-the-first-environment.md) | Local is the first environment in the promotion chain | Accepted |
| [ADR-0025](adr/0025-one-platform-applicationset-cluster-secret-values.md) | One platform ApplicationSet; values and sync switch per cluster | Accepted |
| [ADR-0026](adr/0026-local-secret-store-outside-the-cluster.md) | The local cluster secret store runs outside the cluster | Accepted |
