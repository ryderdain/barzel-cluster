# Security Considerations

How this platform handles secrets, access, and network exposure. This is the
descriptive companion to [SECRETS.md](SECRETS.md) (the credential/key inventory)
and the [ARCHITECTURE.md](ARCHITECTURE.md) ADRs that justify each choice; the
forward-looking, team-scale version of these topics is in
[LEADERSHIP.md](../LEADERSHIP.md) §4.

Guiding principle: **AWS is the root of trust, and no standing credential is
minted for anything a role can do.** Every human, CI runner, and in-cluster
workload reaches AWS through a short-lived assumed role or the EC2 instance
profile — there is no long-lived access key anywhere in the system except the one
operator IAM key the whole chain bootstraps from (and prod replaces that with SSO).

## Secret management

- **No static cloud credentials in git or in the cluster.** Human/CI access is via
  **assumed IAM roles** through GitHub OIDC federation (ADR-0005) — no static keys
  in CI. In-cluster AWS access (CNPG→S3 backups, EBS CSI, ECR pulls) is via the
  **EC2 instance profile** (`inheritFromIAMRole`), so no second IAM user is ever
  minted (ADR-0010).
- **Encryption at rest under customer-managed KMS keys** — one CMK per purpose
  (state, EBS, backups, ECR), each in a *persistent* Terraform layer so teardown
  never churns it (ADR-0006). Key policies delegate use to IAM rather than naming
  consumers, with one deliberate exception: the EBS CMK grants the EC2 Spot
  service-linked role directly, because a service-linked role runs an AWS-managed
  policy that can't be edited (see [SECRETS.md](SECRETS.md) §1).
- **The right store for each thing.** Pull-through registry credentials live in
  **Secrets Manager** (ECR mandates it); account-bearing *non-secret* config (the
  ECR host, the backup bucket name) lives in **SSM Parameter Store**. The two are
  never conflated, and a registry `read:packages` token is never reused as a
  repo-clone credential — credentials are scoped to one job (ADR-0008).
- **In-cluster secret projection via External Secrets Operator.** The app never
  reads a cloud secret store directly: CNPG generates the `pg-app` credential, and
  ESO projects a templated DSN into the app namespace (ADR-0014). One owner per
  secret, refreshed from source, rotatable without a redeploy.
- **The account id never lands in git.** Manifests carry sentinels resolved at
  bootstrap; the GitOps ApplicationSet reads the real ECR host/bucket from an
  in-cluster cluster-`Secret`'s annotations at render time (ADR-0016). `backend.hcl`
  and all `*.tfvars` / `*.tfstate` / saved plans are gitignored.
- **Scripts carry references, not values.** Mutating scripts *emit* their commands
  for preview; a secret is referenced by env-var name (`$GHCR_TOKEN`) and expanded
  only by the downstream shell, so a dry run never prints it. The one secret with a
  git-managed shape (the ArgoCD repo deploy key) is committed only as a `.example`;
  the real file is gitignored and operator-staged.
- **The full inventory** — every key, secret, SSM parameter, in-cluster Secret, and
  gitignored credential file, with how each rotates — is [SECRETS.md](SECRETS.md).

## Access control

- **Federated, least-privilege, split by verb.** GitHub OIDC mints two roles — a
  read-only `brzl-tofu-plan` (for PR plan review in CI) and `brzl-tofu-apply`
  (for merges) — so a plan can't mutate and CI holds no static key (ADR-0005). The
  one human IAM user the chain assumes from is the documented root of trust; the
  prod path replaces it with IAM Identity Center / SSO.
- **Node access is SSH-over-SSM, never inbound `:22`.** Operators reach nodes via
  `aws ssm start-session` with an `AWS-StartSSHSession` ProxyCommand tunnel to the
  node's local sshd; the security group opens **no** inbound SSH, and the Kubernetes
  API is reachable only from a tight admin `/32` that the `20-security` layer
  auto-detects at apply time (ADR-0004). Access is therefore IAM-gateable and fully
  audited (SSM session logs), and a break-glass key still works over the same tunnel.
- **Operations run from the conductor, not laptops.** Infra/cluster operations run
  from a disposable, SSM-only "conductor" box on a pinned toolchain (ADR-0007), so
  the toolchain is identical across operators, operator entry is IAM-gateable, and
  every action plus the triggering identity is logged. The conductor holds **no**
  repo credential — it runs the operator's approved working tree shipped over an
  audited S3 channel.
- **Saved-plan, gated, per-step.** Every billable/mutating change is
  `tofu plan -out=FILE` → review → `apply FILE` — never `-auto-approve` (which
  re-plans and can drift from what was reviewed), and approval in one step never
  carries to the next.
- **In-cluster RBAC.** ArgoCD is the only writer to the cluster (humans change git,
  not live objects); the optional operator-SSO gateway (Dex→GitHub, ADR-0018) puts
  one sign-on with role tiers in front of the web UIs and extends the same identity
  to the kube-API via OIDC. Where SSO isn't deployed (the AWS path), UI access is
  break-glass `kubectl port-forward` over the API you already hold — nothing is
  exposed publicly.

## Network policies

- **Security groups are the primary network boundary.** The cluster SG admits the
  Kubernetes API (6443) only from the operator `/32`, node-to-node traffic via
  intra-SG references (etcd/kubelet/flannel-VXLAN/NodePort), and egress outbound;
  there is **no** inbound SSH (ADR-0004). The conductor's SG is **egress-only** —
  nothing listens inbound; entry is exclusively through SSM.
- **No public control plane or workload by default.** In dev, nodes sit in public
  subnets with the API still `/32`-locked; the prod posture (documented) moves nodes
  to **private subnets** behind the NAT gateway with `associate_public_ip_address =
  false`, reached only via SSM — so the API and workloads have no public surface at
  all. Egress is via a managed NAT (ADR-0012).
- **Ingress is controlled, not ad-hoc.** k3s ships with Traefik; the SSO gateway
  fronts the web UIs with per-host, per-tier auth and trusted TLS (cert-manager +
  Let's Encrypt, ADR-0018). The demo app and ops UIs are otherwise unexposed.
- **In-cluster micro-segmentation is the explicit next step.** This PoC relies on
  the SG perimeter and namespace separation; it does **not** yet ship Kubernetes
  `NetworkPolicy` objects. The production hardening is default-deny `NetworkPolicy`
  per namespace (e.g. only the app namespace may reach CNPG on 5432, only
  monitoring may scrape), enforced by the CNI — k3s's default flannel has no
  NetworkPolicy enforcement, so this pairs with swapping the CNI to Calico/Cilium.
  Called out honestly as a gap, not claimed as done.

## At-rest and in-transit encryption (summary)

- **At rest:** node root volumes + gp3 PVCs (EBS CMK), the CNPG/Barman S3 backup
  bucket (SSE-KMS, bucket policy rejects non-SSE-KMS uploads), ECR image storage,
  and the Terraform state bucket — all under customer-managed CMKs (ADR-0006).
- **In transit:** the kube-API and SSO hosts terminate TLS (Let's Encrypt for the
  SSO edge); the backup bucket policy denies non-TLS (`aws:SecureTransport`) access;
  intra-cluster PKI is k3s-managed.
- **Runtime:** the demo app builds to a **distroless, non-root** image; nodes
  require **IMDSv2** (token-bound metadata, so instance-role creds resist SSRF-style
  metadata theft). Admission control / runtime scanning is a documented prod
  addition (see [LEADERSHIP.md](../LEADERSHIP.md) §4).
