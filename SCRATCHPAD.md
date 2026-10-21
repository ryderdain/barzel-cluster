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

*(2026-10-21, opus. Pruned to the current state. The history is in git,
the plan in [BACKLOG.md](BACKLOG.md), the records in
[RETROSPECTIVE.md](RETROSPECTIVE.md).)*

**Pass 6 (logs) DONE and user-verified** (RETROSPECTIVE 2026-10-21),
merged to `main`. Two Loki stores in namespace `logs`, the in-cluster
collector, the collector beside the cluster (`brzl-log-collector`, queue in
`var/log-store/local/queue/`), kube-prometheus-stack on every substrate,
Grafana at `/grafana/`. The local cluster is down after the test.

**Facts to keep in mind:** a portal location must not set its own
`proxy_set_header` (it then inherits none). Loki with auth off stores
everything under the tenant `fake`. The ApplicationSet's helm keys are
listed in its header. The collector's OTLP receiver takes records from
anyone who reaches it (open item).

**▶ NEXT: pass 6a, SSO** (BACKLOG item 5): Dex and oauth2-proxy in front
of nginx, leading to the admin portal; it replaces the legacy local SSO
path. Start with a short design round.
