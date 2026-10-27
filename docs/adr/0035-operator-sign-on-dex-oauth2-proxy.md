# ADR-0035 — Operator sign-on: Dex → GitHub, oauth2-proxy, kube-API OIDC

## Status

Accepted, amended Q169–Q183 (2026-10-23). Steps 1 (web sign-on) and 2
(`kubectl` through Dex) built in pass 6a · **Date:** 2026-10-14 (split
from ADR-0018, 2026-06-04)

## Context

ADR-0018 bundled sign-on (Dex as the OIDC issuer backed by
GitHub, oauth2-proxy as the gate, the kube-API server trusting Dex, role
tiers by GitHub email) with the edge that served it (one host and one
oauth2-proxy for each service, Traefik `IngressRoute` objects, a wildcard
certificate from Let's Encrypt by DNS-01 at FreeDNS). ADR-0028 replaces the
edge with the admin portal. This record carries sign-on, which pass 6a
builds on the new platform.

## Decision

- **Dex is the OIDC issuer, with GitHub as the identity provider.** One
  sign-on for the web UIs and for `kubectl`: the kube-API server trusts
  Dex, so a person's GitHub identity is their cluster identity.
- **oauth2-proxy gates the admin portal**, in front of nginx with
  `auth_request` (ADR-0028). Sign-on leads to the portal; the portal also
  works without sign-on, for an environment that has none.
- **Role tiers by identity** (admin, operator, viewer), mapped to Argo CD,
  Grafana and Kubernetes RBAC.
- **Local and remote alike**: the same Dex and oauth2-proxy on every
  substrate; only the entry point differs (ADR-0028, pass 8).
- The Let's Encrypt by DNS-01 mechanism from ADR-0018 is reused by
  ADR-0028's `letsencrypt` mode, with the certificate kept in the cluster
  secret store.

## Consequences

- A break-glass record (pass 6b) can name the person who acted, because
  the identity exists before pass 6b.
- The CLI tools need the same identity: the Argo CD CLI and `kubectl` log
  in through Dex; pass 6a designs the copy-paste instructions for the
  portal.
- Dex's own secrets (the GitHub OAuth client, cookie secrets) come from the
  cluster secret store, not from environment exports as in the legacy
  `--with-sso` path.

## Amendment (pass 6a design, Q169–Q183, 2026-10-23)

- **Three access tiers, from GitHub teams** (Q169, Q170, Q173, Q182):
  `brzl-admins`, `brzl-operators` and `brzl-auditors` in the organization
  (`BRZL_SIGN_ON_ORG`). One set for every environment. Each environment
  decides what each tier may do. Dex admits only members of the three
  teams, and the gate refuses anyone else (Q179). A workload viewer tier
  waits (BACKLOG 24).
- **Two layers** (Q171): nginx asks oauth2-proxy about each request
  (`auth_request`), and Argo CD and Grafana are clients of Dex themselves.
  No application trusts a header that another pod set.
- **Dex under the portal**, at `https://<portal host>/dex` (Q172), with its
  state in memory (Q178). Dex and oauth2-proxy come from their Helm charts,
  in the namespace `sign-on`.
- **The built-in logins are off** (Q175): Argo CD's admin, and Grafana's
  login form and basic auth. The emergency path is the CLI with the
  cluster-admin kubeconfig. BACKLOG 23 examines that kubeconfig on a
  public cloud.
- **Sign-on in every environment** (Q177). This replaces "the portal also
  works without sign-on" (ADR-0028).
- **One GitHub OAuth App for each environment** (Q176), owned by the
  organization. Its `read:org` scope is wider than a GitHub App's (see
  SECURITY.md, "What GitHub gives Dex at sign-on").
- **The access steps** are in `driver/access/github.sh` (`teams`,
  `oauth_app`, `sign_on_check`, Q183). Phase 25 seeds the store.
- **`kubectl` through Dex** is step 2 of this pass (Q174).

### As built (pass 6a, step 1)

- The pods of Argo CD, oauth2-proxy and Grafana reach Dex at the issuer
  URL, through the portal, as browsers do. On k3d, a rule in k3s's CoreDNS
  makes the portal's host name the portal's Service (phase 10). In
  `local-ca` mode each client trusts the store's CA, from the store
  (`portal-ca`).
- Argo CD's `oidc.config` names its issuer, client secret and CA as
  `$brzl-argocd-oidc:<key>`. Phase 25 writes that Secret from the store,
  as it writes Argo CD's repository Secrets. argocd-server reads it only
  when it starts, and it starts before External Secrets exists (found in
  the live test). Phase 25 restarts argocd-server when the Secret changes.
- **Outside the gate:** Dex (`/dex/`), oauth2-proxy (`/oauth2/`), the
  workloads (Q144), and Argo CD's public settings
  (`/argocd/api/v1/settings`). The Argo CD CLI reads those settings before
  it signs in. After `argocd login --sso`, the gate accepts the CLI's token
  from Dex (`skip_jwt_bearer_tokens`, the public client `argo-cd-cli`).
- Phase 40 checks the parts of sign-on but cannot sign in: the redirect to
  sign in, Dex at the issuer URL, the issuer in Argo CD's settings, and
  Grafana's health.
- The legacy `--with-sso` path is removed
  (`gitops/clusters/local/{k3d-up.sh,sso/,kustomization.yaml,namespaces.yaml}`,
  `gitops/bootstrap/create-sso-secrets.sh`).

### As built (pass 6a, step 2: `kubectl` through Dex, Q186–Q191)

- The kube-API trusts Dex through a structured `AuthenticationConfiguration`
  (`apiserver.config.k8s.io/v1beta1` on k3s v1.31), a file that phase 10
  writes into the run directory and the server node mounts. The API server
  reads it again when it changes. Its path is a k3s argument, set when the
  cluster is made. The person is `oidc:<login>` (`preferred_username`), and
  the teams are `oidc:<org>:<team>`. The audience is the public Dex client
  `kubernetes` (Q190).
- On the nodes and in CoreDNS, the portal's host name is the portal's fixed
  Service address (`BRZL_PORTAL_CLUSTER_IP`, k3d `--host-alias`, Q186).
  This replaces the CoreDNS rewrite rule of step 1. The fixed address is
  local only (the overlay `gitops/clusters/local/portal/`), a stand-in for
  public DNS, in the band of k3s's Service range that Kubernetes keeps for
  fixed addresses.
- Phase 10 writes `kubeconfig-sign-on` beside the admin kubeconfig (Q188).
  Its user runs kubelogin (in kiesei, pinned) with the browser callback on
  localhost (Q187). kiesei has the host's network. kubelogin keeps the
  tokens in `oidc-cache/` in the run directory (Q189).
- The bindings for the tiers are `gitops/clusters/<env>/access/`. Admins
  are `cluster-admin`, and operators and auditors are `view` (Q170).
  Narrower roles are BACKLOG 30.
- From the security review of 2026-10-26: Dex's ID tokens last 1 hour, and
  its refresh tokens 7 days (Q191). The gate refreshes its session every
  hour (`cookie_refresh`), and Grafana uses refresh tokens, so a removed
  person loses access within the hour. Phase 40 checks that Dex advertises
  PKCE S256. A NetworkPolicy admits only the collector, Grafana and the
  store itself to the admin log store.
