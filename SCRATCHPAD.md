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

**BACKLOG 20 BUILT on branch `item-20-sync-retries`; the live test is
next** (Q167, Q168, ADR-0025 amendment). Sync retries have no limit.
Phase 40's wait names an Application that fails 3+ times (not Synced).
kube-state-metrics exposes `brzl_argocd_app_sync_retries{name,phase,sync}`;
the alert `BrzlSyncFailing` fires at 3 (warning) and 5 (critical) when not
Synced. Verified: renders; kube-state-metrics with the config against the
live cluster (it showed the stale `monitoring` record: Failed, 5, Synced,
so the condition needs `sync`); promtool rule tests (stale record quiet,
failing sync warns at 3 and goes critical at 5, recovered quiet). The
ApplicationSet change reaches the cluster only through phase 30
(BACKLOG 15). BACKLOG 21: a channel for alerts.

Live test 2026-10-22, 13:33Z: phase 30 looped "pod not found; reattaching".
Race: the conductor scaled itself to zero (30 min idle) in the second
conductor.sh woke it; conductor.sh chose the terminating pod. Fixed in
conductor.sh: claim a Ready, non-terminating pod, reset its idle timer,
confirm replicas=1 (3 attempts); stop with a clear message when the pod is
gone (it reattached for up to an hour before).

**▶ NEXT:** the user's live test of BACKLOG 20, then pass 6a, SSO
(BACKLOG item 5), with a short design round.
