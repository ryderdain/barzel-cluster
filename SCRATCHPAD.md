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

**▶ NEXT: pass 6a, SSO** (BACKLOG item 5): Dex and oauth2-proxy in front
of nginx, leading to the admin portal; it replaces the legacy local SSO
path. Start with a short design round. Open: BACKLOG 21 (an alert
channel) fits with 6a or later.
