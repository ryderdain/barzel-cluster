# SCRATCHPAD — working memory (volatile, user-exposed)

The agent's short-term store: session comments, considerations, partial
conclusions, and state worth surviving a context compaction — kept here so the
user can see (and correct) the working memory at any time. Works **in tandem**
with the agent's internal cycles, not instead of them.

**Contract:**

- Freely written and rewritten during a session; stale content is pruned, not
  preserved. Nothing here is a record — durable outcomes graduate to
  [RETROSPECTIVE.md](RETROSPECTIVE.md) once user-verified; planned work moves
  to [BACKLOG.md](BACKLOG.md).
- Update it at natural checkpoints: when picking up a task, on a significant
  finding or direction change, and before ending a session.
- The user may edit or annotate at will; treat their text as instruction.

---

## Current focus

*(2026-10-15, fable. Pruned to the current state; the history is in git,
the plan in [BACKLOG.md](BACKLOG.md), the records in
[RETROSPECTIVE.md](RETROSPECTIVE.md).)*

**Branch `pass-5c-portal`** (checked out in the user's tree), from `main`
84bb4b1. Pass 5c, the admin portal. Design round done: Q126–Q137
([ADR-0028](docs/adr/0028-admin-portal.md) amended by
[ADR-0036](docs/adr/0036-cert-manager-and-local-stand-ins-for-public-services.md)).

**Built (static checks pass, live test pending):**

- `gitops/infrastructure/portal/` (nginx-unprivileged 1.28, static page,
  Certificate, configMapGenerator), `gitops/clusters/local/portal/`
  (NodePort 30443), `gitops/clusters/local/pki/` (vault-type ClusterIssuer
  to OpenBao + the issuer's service account), `gitops/infrastructure/
  cert-manager/values.yaml` (chart v1.21.2). ApplicationSet: elements
  `cert-manager` (wave 1), `pki` (2), `portal` (4); the Certificate's host
  patched from `brzl.dev/portal-host`. Argo CD under `/argocd`
  (`server.rootpath`, `basehref`).
- Driver: `env/local.env` gains `BRZL_PORTAL_{HOST,TLS,PORT,NODE_PORT}`
  (`local.barzel.sh`, `local-ca`, 443, 30443) and `BRZL_DNS_*`. k3d adapter:
  host port 443 → NodePort, `--disable=traefik,servicelb`, a CoreDNS
  stand-in container (`driver/substrates/k3d-dns.Corefile`, 127.0.0.1:1053)
  with a resolver-file warning. OpenBao adapter: `secret_store_pki_up/
  _check` (PKI engine, root CA once, role `portal`, auth role
  `cert-manager`, policy `pki-issuer`; `ca.crt` beside the trust files);
  the `driver` policy gains pki paths (an OLD STORE MUST BE PURGED once).
  Phase 25 calls them; phase 30 writes the annotation; phase 40 checks
  `https://local.barzel.sh/` and `/argocd/` with `--resolve` + `--cacert`.
- Docs: ADR-0036; SPEC §1 (the two local goals) and §3; README status;
  LOCAL.md "Use it" (resolver line, trust the CA, purge note); SECRETS
  rows; ARCHITECTURE §1 diagram + index row; GLOSSARY (TLS mode, local
  stand-in); guides `docs/guide/{kustomize,cert-manager}.md` (BACKLOG item
  12, the guidebook); BACKLOG item 13 parks `again <phase>`.

**▶ NEXT: the live test** (the user runs it): purge the store, `down`,
`up` through kiesei with `BRZL_REPO_DEPLOY_KEY`; then the resolver line and
the CA trust; open `https://local.barzel.sh/`. Known risks to watch: Docker
Desktop binding 127.0.0.1:443; the Argo CD readiness probe under
`rootpath`; cert-manager's vault issuer over plain http; the nginx variable
certificate path. After the test: RETROSPECTIVE entry, ADR-0028 status
"built", merge to `main`; then pass 5d (chofesh).
