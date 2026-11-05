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

## The roots of trust (local)

The inventory below is by kind. This section is by root: the few things a
person holds, and what each one opens. Everything in §5 to §8 derives
from one of them ([SECURITY.md](SECURITY.md), "Authentication flows").

**1. The operator's account on the machine.** It holds everything below,
and it is the root that costs the most.

| What it holds | Where | What that opens |
| --- | --- | --- |
| the container engine's socket | the host | root on every node: the k3s PKI, every in-cluster Secret; the store's volume |
| the disk | `var/` | the store's files, the run directories, the log data |
| the `gh` login and the SSH key | `~/.config/gh`, `~/.ssh` | the GitHub root (4) |

Its controls are the machine's own. On a cloud, BACKLOG 23 decides.

**2. The store's files**: `seal.key`, `driver.token`, `recovery.key` in
`var/secret-store/<env>/` (§5).

| Derives | Lands in | Ends or rotates |
| --- | --- | --- |
| the store itself | the volume `brzl-openbao-data` | a lost seal key is a lost store: purge (LOCAL.md) |
| the entries `repo-deploy-key`, `workload-*`, `sign-on-*`, `grafana-admin`, `smoke` (§6) | the store, then the cluster (phase 25, External Secrets) | §6, "Rotation & lifecycle" |
| the PKI CA: `portal-tls`, `log-intake-tls`, the log-shipper client certificate, `portal-ca` | the cluster; `var/secret-store/<env>/log-shipper/` | 90 days (cert-manager renews), 30 days (phase 10 issues again) |
| the auth roles `eso` and `cert-manager`, and the reviewer token | the store; `brzl-system/openbao-auth-token` | phase 25 writes them again |

**3. The cluster-admin kubeconfig**: `var/run/<env>/<run>/kubeconfig`
(§8). It ends with the cluster (`cluster teardown`).

| Derives | Made by |
| --- | --- |
| the conductor (a service account with `cluster-admin`) | phase 25 |
| every in-cluster Secret that a phase writes: `repo-barzel-cluster`, `workload-github-app`, `brzl-argocd-oidc`, `openbao-auth-token` | phase 25 |
| the kube-API's trust in Dex, and `kubeconfig-sign-on` (no secret in either) | phase 10 |
| the emergency path when Dex or GitHub is down | ADR-0035 (Q175); BACKLOG 23 on a cloud |

**4. The operator's `gh` login**, with the SSH key for the deploy key.
The platform removes nothing on GitHub.

| Derives | Lands in | Ends or rotates |
| --- | --- | --- |
| the teams `brzl-admins`, `brzl-operators`, `brzl-auditors` | GitHub | membership, at GitHub; in effect within the hour (SECURITY.md, "Sessions and revocation") |
| the OAuth App of each environment (client id and secret) | `var/access/github/<org>/`, the store (`sign-on-github-*`), Dex | "Rotation & lifecycle" |
| the GitHub App `brzl-reader-<org>` (id, key, installation) | the files, the store, Argo CD's `repo-creds` | "Rotation & lifecycle" (ADR-0034) |
| the packages token | the files, the store, Zot | "Rotation & lifecycle" |
| the deploy key | the store, Argo CD's repository Secret | at GitHub, then phase 25 |

A person's own credentials are not a root of the platform: their GitHub
account, and the sessions it opens (the gate's cookie, Argo CD's and
Grafana's sessions, the `argocd` CLI's token, kubelogin's cache). Their
lifetimes are in [SECURITY.md](SECURITY.md), "Sessions and revocation".

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
| Local secret-store trust (`var/secret-store/dev/`) | **seal.key** (32 bytes, hex; the static seal's key, passed to the OpenBao container through its environment), **driver.token** (policy `driver`), **recovery.key** (to mint a new root token) — all mode 600, gitignored, made once by driver phase 10 | the operator's credential to the local cluster secret store, as an AWS profile is on AWS (ADR-0026). Lost seal key = lost store (purge, docs/LOCAL.md). The store itself: container `brzl-openbao`, volume `brzl-openbao-data` |
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
| PKI engine `pki/` (the root CA "brzl CA for `<host>`") | phase 10 (`secret_store_ca_up`), once | every certificate below; the CA certificate is `var/secret-store/<env>/ca.crt` |
| PKI role `portal`: server certificates only, for the portal's host and the names under it | phase 25 (`secret_store_pki_up`), each run | cert-manager's `ClusterIssuer brzl-portal`: the portal's certificate and the log intake's (ADR-0036, BACKLOG 4a) |
| PKI role `log-shipper`: client certificates only, for the name `log-shipper` only; no auth role names it, so only the driver can ask it | phase 10 (`secret_store_client_cert_up`), each run | the client certificate of the collector beside the cluster (§8) |
| `sign-on-github-client-id`, `sign-on-github-client-secret` | `var/access/github/<org>/oauth-<env>-client-id` and `-client-secret` (the environment's GitHub OAuth App, from `driver/access/github.sh oauth_app`), once | Dex's GitHub connector (ExternalSecret `dex-env`, ADR-0035). Rotate: a new client secret on GitHub, the file, then phase 25 again |
| `sign-on-oauth2-proxy-client-secret`, `sign-on-argocd-client-secret`, `sign-on-grafana-client-secret`, `sign-on-cookie-secret` | random values (32 hex characters), made once by phase 25 | each client of Dex and Dex itself (they must agree); oauth2-proxy's session cookie. A new value signs everyone out |
| `sign-on-issuer` (not a secret) | `https://<portal host>/dex`, each run of phase 25 | Argo CD's `oidc.config` (ExternalSecret `brzl-argocd-oidc`) |
| `portal-ca` (not a secret) | the CA certificate, `var/secret-store/<env>/ca.crt`, each run of phase 25 | the clients of Dex trust the portal with it in `local-ca` mode: oauth2-proxy, Argo CD, Grafana |
| Auth roles `eso` and `cert-manager`; store policies `driver`, `eso-reader`, `pki-issuer` (GLOSSARY, "Roles") | phase 10 (policies, at the store's first start) and phase 25 (auth roles) | ESO's `ClusterSecretStore brzl-secrets` and cert-manager's issuer (ADR-0026, ADR-0036) |

## 7. In-cluster Kubernetes Secrets

| Secret | Namespace | Owner / source | Notes |
|--------|-----------|----------------|-------|
| ArgoCD repo deploy key | `argocd` | applied from gitignored `repo-deploy-key.yaml` ([`.example`](../gitops/bootstrap/repo-deploy-key.example.yaml) committed) | **read-only** GitHub deploy key (ADR-0013) |
| `repo-barzel-cluster` (local) | `argocd` | **driver phase 25-bootstrap**, read FROM the cluster secret store (`secret/repo-deploy-key`), which the phase seeds once from the bootstrap secret source `BRZL_REPO_DEPLOY_KEY` (the private key text; the operator's key file stays outside the repo, e.g. `~/.ssh/sleipnir-brzl-deploy`) | **read-only** GitHub deploy key, one per environment (revoke local without touching dev); the run sheet carries only the variable's name, the key reaches `kubectl` on stdin. **To be replaced by a GitHub App before any environment beyond local** (BACKLOG gate, Q61) |
| `workload-github-app` | `argocd` | **driver phase 25-bootstrap**, from the store | Argo CD `repo-creds` for `https://github.com/<org>` (type git, App id, installation id, private key); the ApplicationSet's SCM generator names it (`appSecretName`) |
| `openbao-auth-token` | `brzl-system` | **driver phase 25-bootstrap** (long-lived service-account token) | the reviewer token OpenBao uses to verify ESO's tokens against the cluster API (Kubernetes auth, `system:auth-delegator`); its value is handed to the store once, on stdin (ADR-0026) |
| `portal-tls` | `portal` | **cert-manager**, from the `ClusterIssuer brzl-portal` of the environment (`gitops/clusters/<env>/pki/`; local: OpenBao's PKI engine, outside the cluster) | the admin portal's certificate and key (ADR-0028, ADR-0036); 90 days, renewed after 60; nginx reads it at each handshake. The CA's key never leaves the store; the CA certificate (public) is `var/secret-store/<env>/ca.crt` |
| (OpenBao auth role `cert-manager`) | — | **driver phase 25-bootstrap** | lets the service account `cert-manager/brzl-pki-client` log in with policy `pki-issuer`: it may only ask the `portal` role to sign (ADR-0036) |
| `log-intake-tls` | `logs` | **cert-manager**, from the `ClusterIssuer brzl-portal` (PKI role `portal`); the Certificate is in `logs/collector.yaml` | the OTLP receiver's server certificate, `log-intake.<portal host>`, and the CA that its clients must come from (BACKLOG 4a); 90 days, renewed after 60; the receiver reads it again every hour |
| `smoke` | `brzl-system` | **ESO-projected** from `secret/smoke` in the cluster secret store | the pass-5 smoke value: phase 25 writes it, phase 40 compares hashes; not a credential |
| `argocd-initial-admin-secret` | `argocd` | auto-generated by the ArgoCD install | not used: the admin login is off since sign-on (`admin.enabled: false`, Q175). In an emergency, use `argocd --core` with the kubeconfig |
| `grafana-admin` | `monitoring` | local: **ESO-projected** from `secret/grafana-admin` in the cluster secret store (the ExternalSecret is in `monitoring/values-local.yaml`); AWS: **bootstrap-created** ([`create-cluster-secrets.sh`](../gitops/bootstrap/create-cluster-secrets.sh)) until the AWS store exists (pass 8) | the Grafana admin user's password (`admin-user` is `admin`, `admin-password`), referenced via `admin.existingSecret`; never in git, stable (vs the chart's regenerating default). Since sign-on no login uses it: the login form and basic auth are off (Q175) |
| `pg-app` | `chofesh` | **CNPG-generated** app-role credential (`username`/`password`/`uri`/…) for the example app's own Cluster `pg` | operator-owned + rotatable; the app reads the `uri` key directly in its own namespace (ADR-0034, pass 5d; the ESO projection of ADR-0014 is gone with the demo-app); superuser access **disabled** (no `-superuser` secret) |
| `brzl-<env>-in-cluster` | `argocd` | declarative ArgoCD cluster Secret | **not a credential** — carries the per-environment values as labels and annotations (`brzl.dev/registry-host`, prefixes, `brzl.dev/backup-bucket`, revision, the `brzl.dev/auto-sync` switch, the `brzl.dev/workload-follow` policy) written at bootstrap (AWS: host from `resolve-ecr-host.sh`, bucket from SSM) or by phase 30-gitops (local); the platform ApplicationSet reads them at render so the account id stays out of git (ADR-0016, ADR-0025) |
| `dex-env` | `sign-on` | **ESO-projected** from the store (`gitops/infrastructure/sign-on/secrets/`) | Dex's environment: `GITHUB_CLIENT_ID`, `GITHUB_CLIENT_SECRET` (the OAuth App) and the secret of each static client (`OAUTH2_PROXY_`, `ARGOCD_`, `GRAFANA_CLIENT_SECRET`) (ADR-0035) |
| `oauth2-proxy` | `sign-on` | **ESO-projected** from the store | the portal's gate: `client-id`, `client-secret`, `cookie-secret` (`config.existingSecret`) |
| `brzl-argocd-oidc` | `argocd` | **driver phase 25-bootstrap**, from the store (`sign-on-argocd-client-secret`) and the CA file, labelled `app.kubernetes.io/part-of: argocd` | `issuer`, `clientSecret`, `rootCA`, which Argo CD's `oidc.config` names as `$brzl-argocd-oidc:<key>`. Not from ESO: argocd-server reads it only when it starts, and it starts before ESO exists. Phase 25 restarts argocd-server when the Secret changes |
| `grafana-oidc` | `monitoring` | **ESO-projected** from the store | `GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET`, Grafana's client secret (`envFromSecret`) |
| `portal-ca` | `sign-on`, `monitoring` | **ESO-projected** from the store | not a credential: the store's CA certificate, which oauth2-proxy and Grafana trust when they reach Dex (local-ca mode) |

## 8. Gitignored operator-local files (never committed)

From [`.gitignore`](../.gitignore):

- `var/` — the driver's whole local state, never committed:
  - `var/run/<env>/<run>/kubeconfig` — the cluster's **cluster-admin**
    kubeconfig, written by phase 10. The run directory also holds every run
    sheet and output.
  - `var/run/<env>/<run>/kubeconfig-sign-on` — a person's kubeconfig (sign-on
    step 2): the API's address and CA, and the kubelogin command. No secret.
    Beside it, `oidc-cache/` (mode 0700) holds that person's ID token (1
    hour) and refresh token (7 days) from Dex (Q189), and
    `apiserver/authentication-config.yaml` is the kube-API's trust in Dex:
    the issuer, the audience and the store's CA certificate (public),
    mounted into the server node. `argocd-config` is the Argo CD CLI's
    session (its token and refresh token from `argocd login --sso`),
    written by the kiesei shell's `argocd` on first use, mode 0600.
  - `var/secret-store/<env>/` — `seal.key`, `driver.token`, `recovery.key`
    (§5), `ca.crt` (public), and `zot-credentials.json`. That last file is
    Zot's upstream credentials for `ghcr.io`, the packages user and token.
    Phase 25 writes it from the store, mode 0600. Phase 10 mounts it into
    Zot (`{}` until written), and Zot restarts when it changes.
  - `var/secret-store/<env>/log-shipper/` — `tls.crt`, `tls.key` and
    `ca.crt`, mode 0600: the client certificate of the collector beside
    the cluster, from the PKI role `log-shipper` (BACKLOG 4a). Phase 10
    issues it on every run, valid for 30 days. With it, anything can
    write into the admin log store, so it is a credential.
  - `var/log-store/<env>/` — the log data kept outside the cluster
    (ADR-0027). `admin/` is the admin log store's data, and `cold/` is the
    cold log store's (pass 6c). `queue/` holds the
    queue and read positions of the collector beside the cluster.
    `openbao-audit/` holds the secret store's audit log. They hold no secret
    values. The API audit log has metadata only, and OpenBao writes a hash
    of each secret in its audit log, not the value. They do show who did
    what, and the run outputs show the commands that ran. Treat them as
    confidential.
  - `var/access/github/<org>/` — the six files `driver/access/github.sh`
    leaves: the App's id, slug and private key, the installation id, the
    packages user and token. For sign-on, two more for each environment:
    `oauth-<env>-client-id` and `oauth-<env>-client-secret`, the OAuth App
    of that environment. Phase 25 seeds the store from them. You can
    delete the directory after the first bootstrap. The store keeps the values.
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
- **Deploy key:** rotate at GitHub and re-apply the Secret. It is
  bootstrap-time material. Argo CD's admin login is off (sign-on).
- **Operator IAM key:** the only long-lived static credential — the prod path
  replaces it with IAM Identity Center / SSO (no standing key).
- **Sign-on (ADR-0035):** to rotate the OAuth App's client secret, make a
  new one on GitHub and put it in
  `var/access/github/<org>/oauth-<env>-client-secret`. Then run phase 25
  again. ESO brings it to Dex within an hour, or restart Dex. The clients'
  secrets and the cookie secret are made once. To rotate one, delete it in
  the store and run phase 25 again, then restart Dex and that client. The
  clients `argo-cd-cli` and `kubernetes` are public: no secret. To revoke
  a person, remove them from the team on GitHub. The gate, Grafana and
  kubelogin refresh their tokens every hour, and Dex refuses the refresh.
  So their access ends within the hour. Argo CD's UI ends when its token
  expires (1 hour). To end every `kubectl` session at once, restart Dex
  (its refresh tokens are in memory); to end one person's, delete their
  `oidc-cache/`. None of these are ever committed.
