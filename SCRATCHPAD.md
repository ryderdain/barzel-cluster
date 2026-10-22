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

**Pass 6 and item 4a DONE and user-verified** (RETROSPECTIVE 2026-10-21
and 2026-10-22), merged to `main`. Two Loki stores, two collectors with
mutual TLS between them (store CA; client-only role `log-shipper`, issued
by phase 10; server certificate `log-intake.<host>` from cert-manager),
metrics and Grafana on every substrate. The local cluster is up.

**Facts to keep in mind:** a portal location must not set its own
`proxy_set_header`. Loki with auth off stores everything under the tenant
`fake`. The store's CA is made in phase 10; the portal role is
server-only. Argo CD stops after five failed syncs of one commit (BACKLOG
20): a passing DNS fault needed a refresh and a sync by hand.

**▶ NEXT:** the user's decision on BACKLOG 20 (retry limit), then pass 6a,
SSO (BACKLOG item 5), with a short design round.
