# Runbook — Access & Onboarding

Audience: team leads granting/revoking access, and engineers or CI pipelines
that need to act on the platform. Companion: [BOOTSTRAP.md](BOOTSTRAP.md)
(creates the trust anchor), [TEARDOWN.md](TEARDOWN.md). Design context:
[ARCHITECTURE.md](ARCHITECTURE.md) (ADR-0005, constrained-identity deployment).

Status legend: ✅ live · 🔜 pending.

## Principle — no long-lived credentials

Nobody and nothing deploys with static AWS keys. The trust anchor in
[`terraform/identity/`](../terraform/identity/) (admin-run once, [BOOTSTRAP.md](BOOTSTRAP.md)
phase 1) issues **federated, least-privilege roles** that humans and CI *assume*
for the duration of a task:

| Role | Permissions | Assumed by |
|------|-------------|------------|
| `brzl-tofu-plan` | `ReadOnlyAccess` + state read + lock + state-KMS decrypt | reviewers, CI plan jobs |
| `brzl-tofu-apply` | `PowerUserAccess` + scoped IAM on `brzl-*` + `PassRole` to EC2 | maintainers, CI apply-on-merge |

Two trust paths reach those roles: **GitHub Actions OIDC** (scoped to the repo /
default branch — no secrets in CI) and **named operator ARNs** in
`operator_principal_arns` (humans, until IAM Identity Center is enabled).

## Onboard a human operator ✅

1. The new operator has an IAM identity (or, preferred, an Identity Center user —
   see below). Capture their principal ARN.
2. Add it to `operator_principal_arns` in `terraform/identity/terraform.tfvars`
   (gitignored). Plan + apply `terraform/identity/` under an admin or the apply
   role. **Result:** they can now assume `brzl-tofu-plan` / `brzl-tofu-apply`.
3. They assume a role per session — never store keys:
   ```sh
   cd terraform/identity
   aws sts assume-role \
     --role-arn "$(tofu output -raw tofu_plan_role_arn)" \
     --role-session-name "$(whoami)-plan"
   # export the returned AccessKeyId / SecretAccessKey / SessionToken, then run tofu.
   ```
4. Grant least privilege: most engineers get **plan** only; **apply** is for
   maintainers. Use the kiesei container / bootstrap VM for long ops so a
   session expiry can't orphan a half-finished apply ([UPGRADE.md](UPGRADE.md)).

## Onboard a CI pipeline ✅

GitHub Actions assumes a role directly via OIDC — no stored secrets:
```yaml
permissions:
  id-token: write          # required for OIDC
  contents: read
steps:
  - uses: aws-actions/configure-aws-credentials@v4
    with:
      role-to-assume: <brzl-tofu-plan or -apply role ARN>
      aws-region: eu-central-1
```
Convention: plan on every PR (read-only role); apply on merge to the default
branch (apply role). The `sub` condition in `terraform/identity/` pins which
repo/branch may assume each role — widen it deliberately, never to `*`.

## Node shell access — SSM Session Manager ✅

Operators do **not** SSH to nodes over the network. Access is via **AWS SSM
Session Manager**: the node's SSM agent holds an *outbound* channel to the SSM
service, and the operator's session rides it. The cluster security group leaves
**no inbound `:22` open** (`20-security` sets `enable_ssh_ingress = false`) and
the node role carries the SSM grant (`30-iam`, module `enable_ssm = true`).

Why this over an open SSH port / bastion:
- **No inbound port, no public IP required** — smaller attack surface; prod
  nodes can live in private subnets.
- **IAM-gated + audited** — access needs `ssm:StartSession` (the assumed
  `brzl-tofu-apply` role has it via PowerUser), and sessions are logged.
- **Key is necessary-but-not-sufficient** — the break-glass SSH key still
  authenticates *over the tunnel*, but is useless without SSM/IAM rights too.

Prerequisites: assume `brzl-tofu-apply` (so `AWS_PROFILE` + region are set), and
have the **`session-manager-plugin`** (bundled in the kiesei image, or install
locally). The node's SSM agent is enabled by the Ansible `base` role (Noble
preinstalls it).

**Interactive shell** into a node (target = EC2 instance-id):
```sh
aws ssm start-session --target i-0123456789abcdef0
```

**Ansible** needs no extra steps — `ansible.cfg` carries an SSH-over-SSM
`ProxyCommand` and the generated inventory uses the instance-id as `ansible_host`:
```sh
AWS_PROFILE=brzl-apply bash inventory/generate-inventory.sh > inventory/dev.yml
AWS_PROFILE=brzl-apply ansible-playbook playbooks/bootstrap.yml
```

**kubectl / API:** in dev, nodes keep a public IP and `:6443` is open to your
`/32`, so kubectl is direct. In prod (private nodes — ADR-0019, **built and
validated 2026-06-10**) the API is reached through an SSM port-forward that
**the driver manages itself**: every kubectl-using `platform.sh` phase calls
`gitops/tools/api-tunnel.sh`, which detects the tunnel topology (kubeconfig
server = `https://127.0.0.1:6443`, in k3s's default TLS SANs), backgrounds the
forward to the primary node, and waits for the port. Nothing for the operator
to remember; drop it with:
```sh
bash gitops/tools/api-tunnel.sh stop_api_tunnel
```

**Break-glass** (SSM agent down on a node): set `enable_ssh_ingress = true` in
`20-security` and apply, then SSH directly with the env's TF-generated key
(`~/.ssh/brzl-<env>-node` — the generated inventory pins it per env). Revert
once recovered.

**Prod hardening (documented, not built for the PoC):** **VPC interface
endpoints** for `ssm`/`ssmmessages`/`ec2messages` so nodes reach SSM with no NAT
(~$65/mo across 3 AZs — why both envs use the existing NAT path). Optionally
stream session transcripts to S3/CloudWatch (KMS-encrypted) for audit. The
private-subnet/no-public-IP half of this list is no longer "documented" — it is
the built prod environment.

## Human SSO via IAM Identity Center 🔜

Not Terraformed (requires AWS Organizations + console enablement — a manual
prerequisite, [BOOTSTRAP.md](BOOTSTRAP.md) phase 1). Once enabled:
- Map an Identity Center **permission set** onto each `brzl-tofu-*` role so
  humans get a portal login → temporary creds, replacing per-user IAM principals
  in `operator_principal_arns`.
- For bare-metal / non-AWS substrate, **Ory (Hydra)** is the documented portable
  alternative (mirrors the ECR→Harbor "cloud-native demo, portable OSS prod"
  thread in [ARCHITECTURE.md](ARCHITECTURE.md)).

## Sign-on — Dex → GitHub (pass 6a)

One GitHub-backed sign-on in front of the admin portal, in every
environment (ADR-0035). The design and its flows are in
[SECURITY.md](SECURITY.md). The steps for the dev environment are in
[LOCAL.md](LOCAL.md#sign-on).

**The three access tiers** are three teams of the GitHub organization. Dex
admits only their members and names them as groups `<org>:<team>`:

| Tier | Team | Argo CD | Grafana | Kubernetes |
| --- | --- | --- | --- | --- |
| admins | `brzl-admins` | `role:admin` | Admin | `cluster-admin` |
| operators | `brzl-operators` | read and sync, no settings | Editor | view |
| auditors | `brzl-auditors` | `role:readonly` | Viewer | view |

The gate (oauth2-proxy in front of nginx) refuses a person in no team. The
workloads are outside sign-on.

**Onboard a person.** Add them to one team on GitHub. Nothing in the
platform changes.

**Offboard a person.** Remove them from the team on GitHub. Their portal
session ends when its cookie expires (7 days). Argo CD's and Grafana's
sessions end at their next sign-in. For a faster end, rotate the cookie
secret ([SECRETS.md](SECRETS.md), "Rotation & lifecycle").

**The Argo CD CLI.** `argocd login <host> --grpc-web-root-path argocd --sso`
signs in through Dex in the browser. The gate accepts the token that the CLI
then holds.

**`kubectl` by GitHub identity** (step 2, Q174). The run directory holds a
second kubeconfig, `kubeconfig-sign-on`, with no secret in it. `kubectl`
with it runs kubelogin, which signs you in through Dex in the browser, one
time, and keeps your tokens in `oidc-cache/` beside it. The kube-API names
you `oidc:<login>` and your teams `oidc:<org>:<team>`. The bindings in
`gitops/clusters/<env>/access/` give the tiers their rights, so the audit
log names the person. The cluster-admin kubeconfig stays for the driver,
and it is the emergency path when Dex or GitHub fails (Q175).

## In-cluster access (kubectl / ArgoCD)

**Set up `kubectl` ✅.** Self-managed k3s has no `aws eks update-kubeconfig`
equivalent — the admin kubeconfig is generated on a control-plane node, not by an
AWS API call. The Ansible k3s role fetches a copy to `ansible/.kube/config-dev.yaml`
(gitignored — it holds client certs), with the server URL rewritten from
`127.0.0.1` to the node's reachable endpoint. To use it as a normal context:

```sh
AWS_PROFILE=brzl-apply bash gitops/tools/kubeconfig-setup.sh
kubectl get nodes
```

`kubeconfig-setup.sh` reuses those fetched admin creds, **re-resolves the current
primary endpoint** from the `50-compute` Terraform outputs (node IPs change when
compute is recreated between sessions — see [poc cost posture](ARCHITECTURE.md#5-cost--lifecycle-posture)),
renames the generic `default` context to **`brzl-dev`**, and merges it into
`~/.kube/config` (backing the file up first) so plain `kubectl` works. Flags:
`--print` (emit to stdout, change nothing — e.g. `> ~/.kube/brzl-dev.yaml`) and
`--endpoint <ip>` (force the API host, skip the Terraform lookup). It only ever
writes your **local** kubeconfig, never a cloud/cluster resource.

- **Reachability:** `kubectl` reaches the API only from the admin `/32` per the
  cluster security group — the `20-security` layer auto-detects the applying host's
  public IP (an `http` data source), so it tracks whichever host (conductor or
  laptop) brought the layer up. If your public IP drifts (new network/VPN/DHCP),
  kubectl hangs — `bash gitops/tools/admin-ip-check.sh` prints the exact
  `20-security` re-apply (auto-detect, no export) to fix it. For a no-public-IP (prod)
  posture, reach the API via the SSM **port-forward** shown above and run
  `kubeconfig-setup.sh --endpoint 127.0.0.1` (or point the kubeconfig at
  `https://localhost:6443`).
- ArgoCD is the deploy path into the cluster — humans change git, not live
  objects ([UPGRADE.md](UPGRADE.md) golden rule). ArgoCD RBAC (reader vs
  syncer) is configured with the GitOps install.
- **Future (IRSA):** a self-published cluster OIDC issuer lets in-cluster
  workloads assume fine-grained IAM roles; for the deliverable, CNPG→S3 stays on
  the EC2 instance profile.

## Offboard / revoke ✅

1. Remove the principal from `operator_principal_arns` (or the Identity Center
   permission-set assignment); apply `terraform/identity/`. Assume-role stops
   immediately for new sessions.
2. For CI, tighten or remove the `sub` condition for the retired repo/branch.
3. In-flight temporary credentials expire on their own (role max-session-duration)
   — there are no long-lived keys to rotate or hunt down. That property is the
   whole point.
