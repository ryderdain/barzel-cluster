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
  manifests, resolved from SSM at bootstrap; the stack composes its S3 backend from the
  caller's account (no `backend.hcl`); the account-primitives' `backend.hcl`
  (identity/conductor) is gitignored (ADR-0013).
- **Secrets that need a git-managed shape are committed only as `.example`** — the
  real file is gitignored (deploy key, pull-through creds, tfvars).
- **A private workload is read with read-only credentials scoped to its
  organization** (ADR-0034): a GitHub App for the repository, a token with
  `read:packages` for the image. The platform never holds a credential that
  can write to the workload's repository.

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
| `ecr-pullthroughcache/brzl-dev-quay` | quay.io `{username, accessToken}` | [create-pullthrough-secrets.sh](../gitops/bootstrap/create-pullthrough-secrets.sh) | ECR pull-through rule (`40-ecr` `quay_credential_arn`) |
| `ecr-pullthroughcache/brzl-dev-github` | ghcr.io `{username, accessToken}` | same | ECR pull-through rule (`40-ecr` `ghcr_credential_arn`); in pass 8 also the workload's private package (ADR-0034), with the `read:packages` token |
| `ecr-pullthroughcache/brzl-dev-dockerhub` | Docker Hub `{username, accessToken}` — a **read-only** access token | same | ECR pull-through rule (`40-ecr` `dockerhub_credential_arn`); needed for Grafana's image (kube-prometheus-stack) |

> **The conductor holds no repo credential.** It runs the operator's approved working
> tree, shipped to the state bucket from the laptop (`ship-repo.sh`) and pulled by the
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
| **Operator laptop** `gh` login (`~/.config/gh/hosts.yml`) | the operator's own GitHub session; `driver/access/github.sh` uses it to register the workload's App and to read the organization's installations (`admin:org` scope) | OAuth token held by `gh`, **operator machine only**; the platform never receives it |

## 5. SSH / node & cluster access

| Item | Where | Role |
|------|-------|------|
| TF-generated node keypair | private key → `~/.ssh/<key_name>` (`local_sensitive_file`, outside repo); public key → `aws_key_pair` (`dev/50-compute`) | **break-glass only** — primary access is SSH-over-SSM, IAM-gated, no inbound `:22` (ADR-0004) |
| TF-generated **conductor** keypair | private key → `~/.ssh/brzl-dev-conductor` (`local_sensitive_file`); public key → `aws_key_pair` (`dev/00-conductor`) | SSH **through the SSM tunnel** (`AWS-StartSSHSession` ProxyCommand) for a raw channel + §1.8 piping — **no inbound `:22`** (egress-only SG). **Lifecycle-scoped**: created and destroyed with the throwaway conductor; not a standing credential |
| Local secret-store trust (`var/secret-store/local/`) | **seal.key** (32 bytes, hex; the static seal's key, passed to the OpenBao container through its environment), **driver.token** (policy `driver`), **recovery.key** (to mint a new root token) — all mode 600, gitignored, made once by driver phase 10 | the operator's credential to the local cluster secret store, as an AWS profile is on AWS (ADR-0026). Lost seal key = lost store (purge, docs/LOCAL.md). The store itself: container `brzl-openbao`, volume `brzl-openbao-data` |
| k3s server join token | generated by k3s, on the server nodes | shared secret binding the 3-server embedded-etcd quorum; not in repo |
| k3s / etcd / kubelet TLS material | generated by k3s on the nodes | cluster PKI; not in repo |

## 6. The cluster secret store (local: OpenBao, ADR-0026)

What the store holds, by path under the `secret` mount. Phase 25 seeds each
entry once and writes the cluster from the store after that. The AWS
adapter (pass 8) keeps the same entries in Secrets Manager.

| Path | Seeded from | Consumed by |
|------|-------------|-------------|
| `repo-deploy-key` | the bootstrap source `BRZL_REPO_DEPLOY_KEY`, once | the Argo CD repository Secret `repo-barzel-cluster` (phase 25) |
| `smoke` | a random value, each run of phase 25 | ESO projects it to `brzl-system/smoke`; phase 40 compares hashes |
| `grafana-admin` | a random value (48 hex characters), made once by phase 25 | ESO projects it to `monitoring/grafana-admin` (Q105, ADR-0027 amendment) |
| `workload-github-app-id`, `workload-github-app-installation`, `workload-github-app-key` | `var/access/github/<org>/` (`app-id`, `installation-id`, `app.pem`), written by `driver/access/github.sh` with the operator's `gh` login | the Argo CD `repo-creds` Secret `workload-github-app` (phase 25); the App `brzl-reader-<org>` is read-only (contents, metadata), private, no webhooks (ADR-0034) |
| `workload-packages-user`, `workload-packages-token` | `var/access/github/<org>/` (`packages-user`, `packages-token`): a classic GitHub token with only `read:packages`, the only kind the container registry accepts | Zot's upstream credentials file (phase 25) |
| PKI engine `pki/` (the root CA "brzl CA for `<host>`", role `portal`), auth roles `eso` and `cert-manager`, policies `driver`, `eso-reader`, `pki-issuer` | phase 25 (`secret_store_pki_up`, `secret_store_bind_cluster`) | cert-manager's `ClusterIssuer brzl-portal` and ESO's `ClusterSecretStore brzl-secrets` (ADR-0036, ADR-0026) |

## 7. In-cluster Kubernetes Secrets

| Secret | Namespace | Owner / source | Notes |
|--------|-----------|----------------|-------|
| ArgoCD repo deploy key | `argocd` | applied from gitignored `repo-deploy-key.yaml` ([`.example`](../gitops/bootstrap/repo-deploy-key.example.yaml) committed) | **read-only** GitHub deploy key (ADR-0013) |
| `repo-barzel-cluster` (local) | `argocd` | **driver phase 25-bootstrap**, read FROM the cluster secret store (`secret/repo-deploy-key`), which the phase seeds once from the bootstrap secret source `BRZL_REPO_DEPLOY_KEY` (the private key text; the operator's key file stays outside the repo, e.g. `~/.ssh/sleipnir-brzl-deploy`) | **read-only** GitHub deploy key, one per environment (revoke local without touching dev); the run sheet carries only the variable's name, the key reaches `kubectl` on stdin. **To be replaced by a GitHub App before any environment beyond local** (BACKLOG gate, Q61) |
| `workload-github-app` | `argocd` | **driver phase 25-bootstrap**, from the store | Argo CD `repo-creds` for `https://github.com/<org>` (type git, App id, installation id, private key); the ApplicationSet's SCM generator names it (`appSecretName`) |
| `openbao-auth-token` | `brzl-system` | **driver phase 25-bootstrap** (long-lived service-account token) | the reviewer token OpenBao uses to verify ESO's tokens against the cluster API (Kubernetes auth, `system:auth-delegator`); its value is handed to the store once, on stdin (ADR-0026) |
| `portal-tls` | `portal` | **cert-manager**, from the `ClusterIssuer brzl-portal` of the environment (`gitops/clusters/<env>/pki/`; local: OpenBao's PKI engine, outside the cluster) | the admin portal's certificate and key (ADR-0028, ADR-0036); 90 days, renewed after 60; nginx reads it at each handshake. The CA's key never leaves the store; the CA certificate (public) is `var/secret-store/<env>/ca.crt` |
| (OpenBao auth role `cert-manager`) | — | **driver phase 25-bootstrap** | lets the service account `cert-manager/brzl-pki-client` log in with policy `pki-issuer`: it may only ask the `portal` role to sign (ADR-0036) |
| `smoke` | `brzl-system` | **ESO-projected** from `secret/smoke` in the cluster secret store | the pass-5 smoke value: phase 25 writes it, phase 40 compares hashes; not a credential |
| `argocd-initial-admin-secret` | `argocd` | auto-generated by the ArgoCD install | rotate/disable after bootstrap |
| `grafana-admin` | `monitoring` | local: **ESO-projected** from `secret/grafana-admin` in the cluster secret store (the ExternalSecret is in `monitoring/values-local.yaml`); AWS: **bootstrap-created** ([`create-cluster-secrets.sh`](../gitops/bootstrap/create-cluster-secrets.sh)) until the AWS store exists (pass 8) | Grafana admin login (`admin-user` is `admin`, `admin-password`), referenced via `admin.existingSecret`; never in git, stable (vs the chart's regenerating default). The admin portal page shows the command that reads it |
| `pg-app` | `chofesh` | **CNPG-generated** app-role credential (`username`/`password`/`uri`/…) for the example app's own Cluster `pg` | operator-owned + rotatable; the app reads the `uri` key directly in its own namespace (ADR-0034, pass 5d; the ESO projection of ADR-0014 is gone with the demo-app); superuser access **disabled** (no `-superuser` secret) |
| `brzl-<env>-in-cluster` | `argocd` | declarative ArgoCD cluster Secret | **not a credential** — carries the per-environment values as labels and annotations (`brzl.dev/registry-host`, prefixes, `brzl.dev/backup-bucket`, revision, the `brzl.dev/auto-sync` switch, the `brzl.dev/workload-follow` policy) written at bootstrap (AWS: host from `resolve-ecr-host.sh`, bucket from SSM) or by phase 30-gitops (local); the platform ApplicationSet reads them at render so the account id stays out of git (ADR-0016, ADR-0025) |
| `dex-github` | `sso` | **bootstrap-created** ([`create-sso-secrets.sh`](../gitops/bootstrap/create-sso-secrets.sh)) | the GitHub OAuth App `clientID`/`clientSecret` for Dex's connector; injected to Dex as env, never in git (ADR-0018) |
| `oauth2-proxy-oidc` | `sso` | **bootstrap-created** (`create-sso-secrets.sh`) | the Dex static-client `client-secret` + a generated `cookie-secret`, shared by the three oauth2-proxies |
| `sso-wildcard-tls` | `sso` | **cert-manager** (Let's Encrypt DNS-01) | the trusted `*.sso.barzel.sh` wildcard cert; Traefik IngressRoute TLS store for every SSO host |
| FreeDNS webhook cred | `cert-manager` | **helm values at install** (`freedns.auth.FREEDNS_USERNAME/PASSWORD` from env) | afraid.org login the DNS-01 webhook uses to write `_acme-challenge` TXT; passed to the chart at bring-up, never in git or an in-cluster Secret (webhook ≥ 2024-11) |

## 8. Gitignored operator-local files (never committed)

From [`.gitignore`](../.gitignore):

- `var/` — the driver's whole local state, never committed:
  - `var/run/<env>/<run>/kubeconfig` — the cluster's **cluster-admin**
    kubeconfig, written by phase 10. The run directory also holds every run
    sheet and output.
  - `var/secret-store/<env>/` — `seal.key`, `driver.token`, `recovery.key`
    (§5), `ca.crt` (public), and `zot-credentials.json`. That last file is
    Zot's upstream credentials for `ghcr.io`, the packages user and token.
    Phase 25 writes it from the store, mode 0600. Phase 10 mounts it into
    Zot (`{}` until written), and Zot restarts when it changes.
  - `var/log-store/<env>/` — the log data kept outside the cluster
    (ADR-0027). `admin/` is the admin log store's data. `queue/` holds the
    queue and read positions of the collector beside the cluster.
    `openbao-audit/` holds the secret store's audit log. They hold no secret
    values. The API audit log has metadata only, and OpenBao writes a hash
    of each secret in its audit log, not the value. They do show who did
    what, and the run outputs show the commands that ran. Treat them as
    confidential.
  - `var/access/github/<org>/` — the six files `driver/access/github.sh`
    leaves: the App's id, slug and private key, the installation id, the
    packages user and token. Phase 25 seeds the store from them. You can
    delete the directory after the first `up`. The store keeps the values.
- `backend.hcl` — account-primitives' state backend config (identity/conductor only; the stack composes its backend, no file)
- `*.tfstate*`, `*tfplan*` — state + **saved plans (can embed resolved secrets)**
- `*.tfvars*` — **except** the committed non-secret per-env stack defs (`stack/aws/<layer>/{dev,prod}.tfvars`); rendered secret/ARN tfvars use `*.auto.tfvars` and stay ignored
- `ansible/.kube/` — fetched kubeconfig (embeds **cluster-admin** client cert/key)
- `gitops/bootstrap/repo-deploy-key.yaml`, `*_deploy_key`, `*_deploy_key.pub` — the real deploy key
- `~/.ssh/<node key>` — node break-glass private key (outside the repo tree)
- `~/.aws/credentials` — the operator IAM user key (outside the repo tree)

## Rotation & lifecycle

- **KMS CMKs:** automatic annual rotation (`enable_key_rotation`); persistent
  across teardown — a CMK only enters its deletion window on an intentional
  destroy of its layer.
- **Pull-through creds:** rotate the upstream token, re-run
  `create-pullthrough-secrets.sh` (create-or-update), no layer re-apply needed.
- **Conductor code transfer:** no rotation — there's no credential. Re-ship with
  `ship-repo.sh` to update the tree; the conductor is disposable (destroy = nothing left).
- **CNPG `pg-app`:** rotate via CNPG; the app's pods read the Secret at start,
  so restart them after a rotation.
- **The workload's App key and packages token (ADR-0034):** rotate at GitHub
  (a new private key for the App, and delete the old one there; a new
  classic token), put the new files in `var/access/github/<org>/`, and run
  phase 25 again. It writes the new values into the store, rewrites the
  Argo CD `repo-creds` Secret and Zot's credentials file, and restarts Zot.
  Argo CD reads the Secret at its next request.
- **Deploy key / ArgoCD admin:** rotate at the GitHub/ArgoCD side and re-apply the
  Secret; both are bootstrap-time material.
- **Operator IAM key:** the only long-lived static credential — the prod path
  replaces it with IAM Identity Center / SSO (no standing key).
- **SSO (ADR-0018):** the GitHub OAuth App client + the Dex↔proxy client secret are
  bootstrap env (`GITHUB_CLIENT_ID/SECRET`, `OAUTH2_PROXY_CLIENT_SECRET`) consumed by
  `create-sso-secrets.sh`; the FreeDNS cred (`FREEDNS_USERNAME/PASSWORD`) is bring-up
  env for the webhook chart. Rotate at GitHub/afraid.org and re-run the bring-up;
  revoke an operator by removing them from the OAuth App (or the email allowlist). The
  LE wildcard auto-renews via cert-manager. None of these are ever committed.
