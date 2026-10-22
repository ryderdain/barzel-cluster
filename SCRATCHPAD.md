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

**BACKLOG 4a BUILT on branch `item-4a-otlp-mtls`; the user's live test
is next.** Q163–Q166: mutual TLS from the store's CA. The receiver's
certificate `log-intake.<host>` comes from cert-manager through the portal
issuer; the client certificate comes from the driver in phase 10 through
the client-only PKI role `log-shipper` (30 days, issued every run). The
portal role is server-only. The store's CA moved to phase 10. gRPC closed.
GLOSSARY gained "Roles" (PKI role, auth role, store policy, Kubernetes
role, cloud role, access tier). Verified without the cluster: renders, a
throwaway mTLS pair (the real shipper config delivered; no certificate,
a server-only certificate and a foreign CA were refused), the two roles in
a throwaway OpenBao. Then pass 6a, SSO (BACKLOG 5).

Live test 2026-10-22: phase 40 hung at `monitoring`. Cause: DNS lookups
from the pods failed in bursts from 11:05 to 12:47 UTC (not 4a); the sync
used its 5 retries; `secret-store` kept a cached comparison error. Fixed
by a hard refresh and one sync (both Synced/Healthy in about 60 s).
BACKLOG 20 parks the retry limit. The user continues with the 4a checks.

Done 2026-10-21 after the merge: every platform record names the node of
the collector that read it (`brzl.collector.node`), so copies of an event
from several nodes are distinguishable; phase 40 checks it. Verified with
a throwaway collector and `otelcol-contrib validate`; live at the next
`up`.
