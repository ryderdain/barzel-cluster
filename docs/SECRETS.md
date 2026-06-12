# Secrets, Keys & Credentials — Inventory

Where every credential, key, and secret in this platform lives, what it protects,
and how it rotates. Companion to [ARCHITECTURE.md](ARCHITECTURE.md) (the ADRs
behind these choices) and the operator runbooks.

## Principles

- **No static cloud credentials in git or in the cluster.** AWS is the root of
  trust. Human/CI access is via **assumed IAM roles** (GitHub OIDC — no static
  keys in CI); in-cluster AWS access is via the **EC2 instance profile** (CNPG
  backups, EBS CSI, ECR pulls) — no second IAM user is ever minted (ADR-0010).
- **Encryption at rest under customer-managed KMS keys** — one CMK per purpose,
  each in a *persistent* Terraform layer so teardown never churns it (ADR-0006).
- **Account id / account-bearing names stay out of git** — sentinels in committed
  manifests, resolved from SSM at bootstrap; `backend.hcl` is gitignored (ADR-0013).
- **Secrets that need a git-managed shape are committed only as `.example`** — the
  real file is gitignored (deploy key, pull-through creds, tfvars).

## 1. KMS customer-managed keys (encryption at rest)

All have `enable_key_rotation = true`; key policy delegates use to IAM, so
consumers are granted in their IAM role, not the key policy (ADR-0006). One
deliberate exception: the **EBS CMK** also names the `AWSServiceRoleForEC2Spot`
service-linked role in its key policy — that role launches spot nodes and must
decrypt/attach their encrypted root volume, but runs an AWS-managed policy that
can't be edited, so the grant can *only* live in the key policy (not IAM).

| Key | Alias | Protects | TF layer | Notes |
|-----|-------|----------|----------|-------|
| State CMK | `alias/brzl-demo-tfstate` | S3 OpenTofu state bucket | `terraform/bootstrap` | persistent |
| EBS CMK | `alias/brzl-dev-ebs` | node root volumes + gp3 PVCs | `dev/15-kms` | persistent; live key migrated out of `50-compute` 2026-06-04 ([UPGRADE.md](UPGRADE.md)); key policy also grants the EC2 Spot SLR (spot-node root-volume attach) |
| Backup CMK | `alias/brzl-dev-backup` | CNPG/Barman S3 backup bucket (default SSE-KMS) | `dev/15-kms` | persistent; bucket policy rejects non-SSE-KMS / wrong-key uploads |
| ECR CMK | `alias/brzl-dev-ecr` | ECR image storage | `dev/40-ecr` (`modules/ecr`) | persistent |

## 2. AWS Secrets Manager (AWS-stored secrets)

| Secret | Contents | Created by | Consumed by |
|--------|----------|-----------|-------------|
| `ecr-pullthroughcache/brzl-dev-quay` | quay.io `{username, accessToken}` | [create_pullthrough_secrets.sh](../gitops/bootstrap/create_pullthrough_secrets.sh) | ECR pull-through rule (`40-ecr` `quay_credential_arn`) |
| `ecr-pullthroughcache/brzl-dev-github` | ghcr.io `{username, accessToken}` | same | ECR pull-through rule (`40-ecr` `ghcr_credential_arn`) |
| `ecr-pullthroughcache/brzl-dev-dockerhub` | Docker Hub `{username, accessToken}` — a **read-only** access token | same | ECR pull-through rule (`40-ecr` `dockerhub_credential_arn`); needed for Grafana's image (kube-prometheus-stack) |

> **The conductor holds no repo credential.** It runs the operator's approved working
> tree, shipped to the state bucket from the laptop (`ship_repo.sh`) and pulled by the
> conductor's `brzl-fetch` via its **instance role** — so there is nothing to
> authenticate to GitHub and no standing clone token (CLAUDE.md §1.8). The transfer
> object (`s3://…tfstate…/conductor-transfer/tree.tgz`) is approved code, not a secret,
> and is swept in teardown.

ECR **mandates Secrets Manager** for a pull-through `credential_arn` (Parameter
Store is rejected) and **requires** the `ecr-pullthroughcache/` name prefix
(ADR-0008). `registry.k8s.io` and `quay.io` are credential-free (no secret);
`ghcr.io` and Docker Hub require an authenticated token.

## 3. SSM Parameter Store (non-secret config)

Plain `String` parameters — **config, not secrets**. Listed here because they are
*account-identifying*, which is exactly why they live in SSM rather than git.

| Parameter | Value | Resolves |
|-----------|-------|----------|
| `/brzl-dev/ecr/registry_host` | `<account>.dkr.ecr.<region>.amazonaws.com` | `__ECR_REGISTRY_HOST__` sentinel at bootstrap |
| `/brzl-dev/backup/bucket_name` | account-bearing CNPG backup bucket | `__BACKUP_BUCKET__` sentinel at bootstrap |

## 4. IAM identities (no static keys)

| Identity | Purpose | Auth |
|----------|---------|------|
| GitHub OIDC provider + `brzl-tofu-plan` / `brzl-tofu-apply` roles | CI/agent plan & apply | OIDC web-identity / `assume-role`; **no static keys in CI or git** |
| `brzl-dev-node` instance profile | in-cluster AWS: CNPG backup (`inheritFromIAMRole`), EBS CSI volume lifecycle, ECR pull + pull-through import | EC2 instance metadata; **no IAM user** |
| **Operator laptop** `~/.aws/credentials` (`default`, user `rdain`) | the one static key — the human root-of-trust the `brzl-apply` profile assumes the apply role from | IAM access key, **operator machine only, never in repo**. Prod: replace with IAM Identity Center / SSO |

## 5. SSH / node & cluster access

| Item | Where | Role |
|------|-------|------|
| TF-generated node keypair | private key → `~/.ssh/<key_name>` (`local_sensitive_file`, outside repo); public key → `aws_key_pair` (`dev/50-compute`) | **break-glass only** — primary access is SSH-over-SSM, IAM-gated, no inbound `:22` (ADR-0004) |
| TF-generated **conductor** keypair | private key → `~/.ssh/brzl-dev-conductor` (`local_sensitive_file`); public key → `aws_key_pair` (`dev/00-conductor`) | SSH **through the SSM tunnel** (`AWS-StartSSHSession` ProxyCommand) for a raw channel + §1.8 piping — **no inbound `:22`** (egress-only SG). **Lifecycle-scoped**: created and destroyed with the throwaway conductor; not a standing credential |
| k3s server join token | generated by k3s, on the server nodes | shared secret binding the 3-server embedded-etcd quorum; not in repo |
| k3s / etcd / kubelet TLS material | generated by k3s on the nodes | cluster PKI; not in repo |

## 6. In-cluster Kubernetes Secrets

| Secret | Namespace | Owner / source | Notes |
|--------|-----------|----------------|-------|
| ArgoCD repo deploy key | `argocd` | applied from gitignored `repo-deploy-key.yaml` ([`.example`](../gitops/bootstrap/repo-deploy-key.example.yaml) committed) | **read-only** GitHub deploy key (ADR-0013) |
| `argocd-initial-admin-secret` | `argocd` | auto-generated by the ArgoCD install | rotate/disable after bootstrap |
| `grafana-admin` | `monitoring` | **bootstrap-created** ([`create_cluster_secrets.sh`](../gitops/bootstrap/create_cluster_secrets.sh)) | Grafana admin login (`admin-user`/`admin-password`), referenced via `admin.existingSecret`; never in git, stable (vs the chart's regenerating default); read by `ui_forward.sh` |
| `pg-app` | `cnpg-demo` | **CNPG-generated** app-role credential (`username`/`password`/`uri`/…) | operator-owned + rotatable; superuser access **disabled** (no `-superuser` secret) |
| `pg-app` | `demo` | **ESO-projected** from `cnpg-demo/pg-app` | only the templated DSN `uri` key; ESO-owned, refreshed from source (ADR-0014) |
| `brzl-dev-in-cluster` | `argocd` | declarative ArgoCD cluster Secret | **not a credential** — carries the account-bearing **host/bucket as annotations** (`brzl.dev/ecr-host`, `brzl.dev/backup-bucket`) written at bootstrap (host from `resolve_ecr_host.sh`, bucket from SSM); the ApplicationSet reads them at render so the account id stays out of git (ADR-0016) |
| `dex-github` | `sso` | **bootstrap-created** ([`create_sso_secrets.sh`](../gitops/bootstrap/create_sso_secrets.sh)) | the GitHub OAuth App `clientID`/`clientSecret` for Dex's connector; injected to Dex as env, never in git (ADR-0018) |
| `oauth2-proxy-oidc` | `sso` | **bootstrap-created** (`create_sso_secrets.sh`) | the Dex static-client `client-secret` + a generated `cookie-secret`, shared by the three oauth2-proxies |
| `sso-wildcard-tls` | `sso` | **cert-manager** (Let's Encrypt DNS-01) | the trusted `*.sso.barzel.sh` wildcard cert; Traefik IngressRoute TLS store for every SSO host |
| FreeDNS webhook cred | `cert-manager` | **helm values at install** (`freedns.auth.FREEDNS_USERNAME/PASSWORD` from env) | afraid.org login the DNS-01 webhook uses to write `_acme-challenge` TXT; passed to the chart at bring-up, never in git or an in-cluster Secret (webhook ≥ 2024-11) |

## 7. Gitignored operator-local files (never committed)

From [`.gitignore`](../.gitignore):

- `backend.hcl` — state backend config (account-bearing names)
- `*.tfstate*`, `*.tfvars*`, `*tfplan*` — state, variable values, **saved plans (can embed resolved secrets)**
- `ansible/.kube/` — fetched kubeconfig (embeds **cluster-admin** client cert/key)
- `gitops/bootstrap/repo-deploy-key.yaml`, `*_deploy_key`, `*_deploy_key.pub` — the real deploy key
- `~/.ssh/<node key>` — node break-glass private key (outside the repo tree)
- `~/.aws/credentials` — the operator IAM user key (outside the repo tree)

## Rotation & lifecycle

- **KMS CMKs:** automatic annual rotation (`enable_key_rotation`); persistent
  across teardown — a CMK only enters its deletion window on an intentional
  destroy of its layer.
- **Pull-through creds:** rotate the upstream token, re-run
  `create_pullthrough_secrets.sh` (create-or-update), no layer re-apply needed.
- **Conductor code transfer:** no rotation — there's no credential. Re-ship with
  `ship_repo.sh` to update the tree; the conductor is disposable (destroy = nothing left).
- **CNPG `pg-app`:** rotate via CNPG; ESO's `refreshInterval` re-projects the new
  value into `demo` automatically.
- **Deploy key / ArgoCD admin:** rotate at the GitHub/ArgoCD side and re-apply the
  Secret; both are bootstrap-time material.
- **Operator IAM key:** the only long-lived static credential — the prod path
  replaces it with IAM Identity Center / SSO (no standing key).
- **SSO (ADR-0018):** the GitHub OAuth App client + the Dex↔proxy client secret are
  bootstrap env (`GITHUB_CLIENT_ID/SECRET`, `OAUTH2_PROXY_CLIENT_SECRET`) consumed by
  `create_sso_secrets.sh`; the FreeDNS cred (`FREEDNS_USERNAME/PASSWORD`) is bring-up
  env for the webhook chart. Rotate at GitHub/afraid.org and re-run the bring-up;
  revoke an operator by removing them from the OAuth App (or the email allowlist). The
  LE wildcard auto-renews via cert-manager. None of these are ever committed.
