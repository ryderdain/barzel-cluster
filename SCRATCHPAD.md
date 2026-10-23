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

*(2026-10-22, opus. Pruned to the current state. The history is in git,
the plan in [BACKLOG.md](BACKLOG.md), the records in
[RETROSPECTIVE.md](RETROSPECTIVE.md).)*

**Pass 6, item 4a and BACKLOG 20 DONE and user-verified**
(RETROSPECTIVE 2026-10-21 and 2026-10-22), merged to `main`. Logs with
two Loki stores and mutual TLS between the collectors; metrics and
Grafana on every substrate; sync retries with no limit, a warning in
phase 40 and the alert `BrzlSyncFailing`. The local cluster is up.

**Facts to keep in mind:** a portal location must not set its own
`proxy_set_header`. Loki with auth off stores everything under the tenant
`fake`. The store's CA is made in phase 10; the PKI role `portal` is
server-only. An Application keeps its last operation record (phase,
retry count) after its resources converge. The conductor scales itself to
zero after 30 minutes idle; `conductor.sh` claims a live pod. A stacked
graph hides series at 0.

**▶ IN FLIGHT: pass 6a, sign-on** (BACKLOG item 5), branch
`pass-6a-sign-on`. Design Q169–Q183 done (ADR-0035 amendment; the decision
log is `notes/DECISIONS.md`, local only). **Step 1, web sign-on, built
2026-10-23; waiting for the user's live test.**

What step 1 built:

- `driver/access/github.sh` `teams`, `oauth_app`, `sign_on_check`;
  `BRZL_SIGN_ON_ORG=tzvat` in `env/local.env`.
- Phase 10: CoreDNS rule (ConfigMap `kube-system/coredns-custom`, the
  portal host is the portal Service in the cluster) and the host run sheet
  `10-host.sh` (resolver, CA trust by OS; Q180); `driver/kiesei.sh` runs it
  on the host after the stream, with the terminal.
- Phase 25: store entries `sign-on-*` and `portal-ca`; error 3 without the
  OAuth App.
- GitOps: `sign-on-secrets` (6 ExternalSecrets), `dex` (chart 0.25.2,
  memory), `oauth2-proxy` (chart 10.6.2), nginx `auth_request`; Argo CD
  OIDC (`$brzl-argocd-oidc:*`), RBAC, admin off; Grafana generic OAuth,
  login form and basic auth off. `portalHostParams` has `suffix`.
- Phase 40: the redirect to sign in, Dex at the issuer, Argo CD names the
  issuer, Grafana healthy, `/apps/chofesh/` open. The Grafana query check
  is gone (it needed the admin password).

Untested by me: the sign-in itself, `argocd login --sso` from kiesei (the
callback on localhost:8085 needs host networking), the host sheet with a
terminal. Next: the user's live test, then step 2 (`kubectl` through Dex).
BACKLOG 21 (an alert channel) fits with 6a or later.
