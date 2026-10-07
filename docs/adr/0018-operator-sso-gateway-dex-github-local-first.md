# ADR-0018 — Operator SSO gateway (Dex→GitHub), local-first

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
cred) are bootstrap-injected as env, never in git (`create_sso_secrets.sh`, [SECRETS.md](../SECRETS.md)).
**Promote to AWS:** the Dex/oauth2-proxy/cert-manager manifests are unchanged; only
point `*.sso.barzel.sh` A records at the Terraform NLB (afraid.org stays the DNS, or
delegate to Route53) and add the API-server OIDC flag to the Ansible `kubernetes` role.
**Authored 2026-06-04; live bring-up pending** the operator's GitHub OAuth App + FreeDNS
credential + `/etc/hosts` (see [LOCAL.md](../LOCAL.md) `--with-sso`, [ACCESS.md](../ACCESS.md)).
