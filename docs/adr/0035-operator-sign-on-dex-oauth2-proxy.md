# ADR-0035 — Operator sign-on: Dex → GitHub, oauth2-proxy, kube-API OIDC

**Status:** Accepted (design; built in BACKLOG pass 6a) · **Date:**
2026-10-14 (split from ADR-0018, 2026-06-04)

**Context.** ADR-0018 bundled sign-on (Dex as the OIDC issuer backed by
GitHub, oauth2-proxy as the gate, the kube-API server trusting Dex, role
tiers by GitHub email) with the edge that served it (one host and one
oauth2-proxy for each service, Traefik `IngressRoute` objects, a wildcard
certificate from Let's Encrypt by DNS-01 at FreeDNS). ADR-0028 replaces the
edge with the admin portal. This record carries sign-on, which pass 6a
builds on the new platform.

**Decision.**

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

**Consequences.**

- A break-glass record (pass 6b) can name the person who acted, because
  the identity exists before pass 6b.
- The CLI tools need the same identity: the Argo CD CLI and `kubectl` log
  in through Dex; pass 6a designs the copy-paste instructions for the
  portal.
- Dex's own secrets (the GitHub OAuth client, cookie secrets) come from the
  cluster secret store, not from environment exports as in the legacy
  `--with-sso` path.
