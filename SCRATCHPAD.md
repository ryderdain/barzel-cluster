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

*(2026-10-19, opus. Pruned to the current state. The history is in git,
the plan in [BACKLOG.md](BACKLOG.md), the records in
[RETROSPECTIVE.md](RETROSPECTIVE.md).)*

**Pass 6 (logs) BUILT on branch `pass-6-logs`; the user's live test is
next.** Design round Q158–Q162 (ADR-0027 amendment, SPEC v0.15): metrics
and Grafana on every substrate (kube-prometheus-stack; its Grafana is the
one viewer), Loki and the collector from Helm charts, the collector beside
the cluster forwards to the in-cluster one and queues on disk. BACKLOG
gained 17 (`state`, read-only), 18 (purge, separate, with safeguards), 19
(low-memory mode).

**What was built:** run directories `cluster-<UTC>Z` / `teardown-<UTC>Z`,
a header line in each run output (driver tests 18/18); phase 10 makes
`var/log-store/local/{admin,queue,openbao-audit}`, the container
`brzl-log-collector`, and the cluster with the API audit policy, the k3s
log file and the admin data's mount; OpenBao's audit device in its config
(the container is replaced once, its data stays); ApplicationSet keys
`moreValueFiles`, `moreValueFilesLocal`, `prefixParams`,
`portalHostParams`, `envParams`; elements `monitoring` (now common),
`log-store-admin`, `log-store-diagnostic`, `log-collector` (namespace
`logs`); phase 25 seeds `grafana-admin` in the store; phase 40 checks
every admin source, the app's logs in the diagnostic store, `/grafana/`.

**Verified without a cluster:** the template patch rendered through Helm
for six elements; the charts rendered; `loki -verify-config` on both
configs; `otelcol-contrib validate` on both collector configs; a Loki
container with the chart's config is ready after ~45 s and indexes the
labels; OpenBao 2.7.1 accepts the declarative audit device (needs `type`
and `path`); uid 10001 writes to a host bind mount.

**Risks for the live test:** k3s `--log` with k3d's `--wait` (if phase 10
hangs at cluster create, that flag is the suspect); first pulls of the new
images through Zot; ESO must project `grafana-admin` before Grafana starts.

**Live test, 2026-10-21:** step 2 failed with "origin not allowed" in
Explore. Cause: the portal's `/grafana/` location set its own
`proxy_set_header` lines, so it inherited no `Host` from the server level.
Fixed in `dae197d`, with a phase 40 check that queries Grafana as a browser
does. The check passed on the live cluster about 60 s after the push.

**▶ NEXT:** the user continues the live test (procedure in the chat), then the
RETROSPECTIVE entry, the memory budget measured into LOCAL.md, merge.
