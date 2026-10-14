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

*(2026-10-14, opus. Pruned to the current state; the history is in git, the
plan in [BACKLOG.md](BACKLOG.md), the records in
[RETROSPECTIVE.md](RETROSPECTIVE.md).)*

**Branch `cleanup-docs`** (checked out in the user's tree). The cleanup round
(Q121), docs only:

1. Platform reframe: SPEC scope, README intro, CLAUDE.md "What this repo
   is", GLOSSARY workload terms, ARCHITECTURE prose; confidential computing
   becomes a guide, not the goal.
2. ADR-0027 logs (Q77–Q102), ADR-0028 admin portal (Q107–Q114), ADR-0029
   the vendored doctrine pin (Q103); their SPEC §3 lines; a report on
   splitting older ADRs (a review agent is reading them).
3. BACKLOG: one line per item, new order (Q120). **Done.**
4. SCRATCHPAD: this. **Done.** Safe point to compact.
5. LOCAL.md: the resource budget (sleipnir 32 GB, huginn 8 GB).

The user reviews the branch as one diff; then merge to `main`.

**Next after the round:** pass 5c, the admin portal (BACKLOG).

**Decisions of 2026-10-14 not yet in an ADR** (the round writes them):

- Logs (Q84–Q102): workload / platform logs; admin log store (Loki, data
  outside the cluster, flush 1m/5m) and diagnostic log store (Loki, in the
  cluster); one node collector (OTel Collector, OTLP); routes in the
  namespace annotation `brzl.dev/log-routes: drop|admin|diagnostic|cold`;
  retention classes `brzl.dev/log-retention: 7d|30d|90d`; Grafana in the
  cluster; UTC with Z; run directories `cluster-<UTC>Z` / `teardown-<UTC>Z`;
  a logfmt header in each run-log. Spike verdict: branch `spike-logs`,
  `spikes/logs/RESULTS.md`.
- Admin portal (Q107, Q112–Q114): one nginx, a static page, relative paths
  (`/argocd/`, `/grafana/`, `/apps/<workload>/`); TLS `letsencrypt` (owned
  domain, certificate kept in the secret store) or `local-ca` (OpenBao PKI).
- Q103: `driver/lib/{runlib,error}.sh` pinned to `ryderdain/bash` master, tag
  `barzel-cluster/2026-10-14`.
- Q115: chofesh becomes the example app; CNPG cluster moves into the app.
- Q118: `promote platform`, `promote workloads`, `promote all` (separate).
- Q119: one stack per substrate (`terraform/stack/<substrate>/<layer>/`);
  "profile" meant substrate.

**State to remember:** the local cluster follows branch `spike-logs` until a
phase-30 run from `main`. `ryderdain/bash` has a local branch
`backup/bash-doctrine-pre-squash`.
