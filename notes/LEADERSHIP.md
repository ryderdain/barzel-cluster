# Leadership Component

My answers to your four prompts I hope come through in part by my overall design
descisions for this platform. I've kept the direct answers to bullets, as asked.
The reasoning for each is the part I'd defend in a review, so where a choice is
load-bearing I say *why*, and where something is the production step past this
PoC I mark it **prod** rather than pretend it's done.

## 1. Team Organization — three DevOps engineers

Three members is too few to wall into silos, so I'd try to offer *ownership* as
the prime differentiaor between who authors a decision, rather than enforcement
of strict roles bundled with access rights. In this way, everyone can
collaborate efficiently and with confidence that any concerns or suggestions
they have are going to the right person.

### Ownership Roles

- **Platform / IaC** — Terraform modules and layers, the conductor toolchain, the
  AWS account and its identity (OIDC roles, KMS). Guards the state backend and the
  blast radius.
- **Cluster / GitOps** — ArgoCD, the ApplicationSet and its sync waves, the
  operators (CNPG, ESO, EBS CSI), the Ansible roles. Owns convergence and the path
  a change takes to production.
- **Reliability / Security** — backups and the restore *drill* (the two are not the
  same thing), monitoring and alerting, the posture in [SECURITY.md](docs/SECURITY.md),
  upgrade choreography, on-call.

### Review process

- Every change is a PR; nothing is `kubectl edit`'d onto a live object (ADR-0013).
  The history *is* the change log and the rollback path (`git revert` → ArgoCD
  re-syncs).
- Plans run in CI under a *read-only* role (`brzl-tofu-plan`); `apply` runs only on
  merge under `brzl-tofu-apply` (ADR-0005). A plan that *cannot* mutate is one an
  agent can review.
- Two-person review for production and for anything that *replaces* a stateful
  resource (EC2/EBS/CMK), touches IAM, or moves the data path.

### Release management

- Promotion is a PR that bumps a pinned version in the target environment — not a
  hand re-run. Sync waves keep the operators ahead of the apps that need them.
- Saved-plan workflow, always (`plan -out` → review → `apply` *that file*); never
  `-auto-approve`, which re-plans fresh and can quietly diverge from what was approved.
- Operations should be conducted by single-purpose scripts which *emit* their commands for
  preview before they run (this goes to a broader vision I'm developing for Bash
  scripts and their appropriate use). Not completely reflected here, due to time
  constraints on robust testing. The method should allow a junior to review and
  learn the actual commands in order before they're run; it provides seniors an
  auditable sanity check on every step.
  
## 2. Multi-Environment Deployments

The repo intends to provide a *composition* of shared modules, never a fork.

### Customer-specific configuration

- Layered Terraform with strict env separation (`environments/{dev,prod}`, per Lee
  Briggs; ADR-0002) over shared modules — a customer is that same module set with its
  own `tfvars` and `backend.hcl`.
- Account-bearing and customer-specific identifiers never enter git: they're
  *derived* from the caller identity or resolved from SSM at bootstrap (ADR-0016), so
  one codebase serves every account without committing any of their names.
- GitOps overlays per cluster — the ApplicationSet injects each cluster's registry
  and bucket from in-cluster annotations at render, so identical manifests render
  correctly against different accounts.

### Infrastructure variations

- A dev or operator runs nodes in public subnets, `/32`-locked; prod flips to
  private subnets with no public IP, through the same modules with different
  inputs — not an assertion: `terraform/environments/prod/` is built and was
  validated live 2026-06-10, NLB-only ingress included (ADR-0019). Capacity
  (`spot`/`on-demand`), size, and node count are configurable.
- Documented descope/upscale levers — `local-path` vs EBS-CSI, NAT vs VPC-endpoint
  egress, single-account vs account-per-customer (ADR-0011).

### Upgrades across customers

- Account-per-customer in prod (ADR-0011), so one customer's upgrade *cannot*
  reach another's. Account segregation in public clouds provides an implicity
  permissions and access perimeter more thoroughly than a namespace or network
  perimeter can.
- All tool and software versions must be pinned, and rolled out in waves; prove
  the path on a canary or demo customer first, watch resolution via GitOps
  convergence and (if any doubts exist) run a restore drill. Upgrades roll out
  through Argo, one PR at a time to catch issues. The mechanism is identical per
  customer (the same ApplicationSet), which is the whole point: an upgrade is
  repeatable, not bespoke. ([UPGRADE.md](docs/UPGRADE.md) has the per-component
  choreography.)

## 3. Reliability

### Repeatable deployments

- Everything in code. Terraform for infra, Ansible for host/k3s bootstrap, ArgoCD
  for the cluster; no click-ops anywhere. I ran a complete from-zero
  bring-up end to end (account bootstrap → conductor → layers → k3s HA →
  GitOps → a seeded data path) in to validate this.
- The conductor pins the toolchain (ADR-0007), so bring-up, recovery, and teardown
  are the *same* operation on every machine — version drift between operators is
  designed out, not policed.

### Automated testing

- What I'd expect to live in CI: `tofu validate`/`fmt`, `tofu plan` for review,
  `shellcheck` on every script, manifest lint. **prod:** policy-as-code
  (OPA/Conftest or Sentinel) to *gate* the plan — no `0.0.0.0/0`, encryption
  required, tags enforced — so a reviewer isn't the only thing between a bad
  diff and production.
- The DR restore drill is, in my opinion, mandatory. The platform proves
  recovery against an exact row-count acceptance target, on a freshly rebuilt
  stack, from the S3 object store alone — and recovers *before* GitOps adopts the
  cluster, so the operator never `initdb`s over the restore. See
  [RECOVERY.md](docs/RECOVERY.md).

### Safe infrastructure changes

- Saved-plan, gated, per step. What I read the plan *for* is replacements of
  stateful resources (EC2/EBS/CMK); a green plan that quietly recreates a volume is
  the one that ruins my day.
- Layered state caps the blast radius: most changes touch one layer, and the
  persistent concerns (KMS, backups, state) live in layers the churned compute layer
  can't destroy (ADR-0006).
- Teardown is reverse-dependency order *plus an explicit leak sweep*; `tofu destroy`
  is necessary but not sufficient. CSI-provisioned EBS volumes, ECR pull-through cache
  repos, and script-created secrets all orphan invisibly; the runbook sweeps them
  ([TEARDOWN.md](docs/TEARDOWN.md)), and that sweep earned its place by catching orphaned
  PVC volumes a layer destroy never sees. Included here for my own bookkeeping.

## 4. Security

The platform's posture is laid out more elaborately in
[SECURITY.md](docs/SECURITY.md); this is how I'd ensure it at team scale. PoC vs.
**prod** highlighted below.

- **Network** — the security-group perimeter is the boundary (API `/32`-locked, no
  inbound `:22`, an egress-only conductor); prod moves workloads to private subnets
  with no public surface and adds **default-deny `NetworkPolicy`** per namespace on a
  policy-enforcing CNI (Calico/Cilium) — the in-cluster micro-segmentation this PoC
  honestly doesn't yet ship.
- **Data** — customer-managed CMKs for every store (EBS, S3 backups, ECR, state),
  TLS in transit, bucket policies that *refuse* non-TLS and non-SSE-KMS writes, and
  backups that are tested, not merely taken; **prod:** data classification and
  per-tenant key isolation.
- **Runtime** — non-root distroless images, IMDSv2-only nodes (so instance-role creds
  don't fall out of an SSRF), read-only rootfs where it's feasible; **prod:** an
  admission baseline (Pod Security Standards / Kyverno) and runtime detection (Falco /
  GuardDuty).
- **Secrets** — no static cloud keys at all (OIDC + instance profile); Secrets Manager
  for secrets and Parameter Store for config, never conflated; ESO projection with one
  owner per secret; **prod:** automated rotation and short-TTL dynamic secrets.
- **Access** — federated, least-privilege, *split by verb* (plan vs apply); node
  access is SSM-only and fully audited; humans sign in through the SSO gateway with
  role tiers (ADR-0018); **prod:** IAM Identity Center retiring the last static
  operator key, with periodic review and just-in-time elevation.
- **Supply chain** — versions and images pinned by digest, immutable ECR tags,
  pull-through only from trusted upstreams, and stored images **scanned with a
  documented fail-on-critical gate** (ECR/Inspector or Trivy; Harbor's built-in Trivy
  for the prod registry — ADR-0008); **prod:** image signing and verification
  (cosign/Sigstore) plus SBOMs, enforced at admission.
