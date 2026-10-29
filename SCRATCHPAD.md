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

*(2026-10-27, fable. Pruned to the current state. The history is in git,
the plan in [BACKLOG.md](BACKLOG.md), the records in
[RETROSPECTIVE.md](RETROSPECTIVE.md).)*

**Pass 6a, sign-on (BACKLOG item 5) DONE and user-verified**
(RETROSPECTIVE 2026-10-23 and 2026-10-27, three entries), merged to
`main`. It built web sign-on through Dex and oauth2-proxy, and `kubectl`
through Dex with the browser callback. The kiesei shell makes the person
the default, and the Argo CD CLI passes the gate. SECURITY.md has the
auth flows as six Mermaid diagrams. The local cluster is up.

**Facts to keep in mind:** a portal location must not set its own
`proxy_set_header`. Loki with auth off stores everything under the tenant
`fake`. The store's CA is made in phase 10; the PKI role `portal` is
server-only. An Application keeps its last operation record (phase,
retry count) after its resources converge. The conductor scales itself to
zero after 30 minutes idle; `conductor.sh` claims a live pod. A stacked
graph hides series at 0. k3d's `--host-alias` does not survive a
container restart (the node runs a hosts script at every start). Docker
Desktop's "Enable host networking" must be on for a callback to reach
the browser. The Argo CD CLI sends its token in a header named `token`.
The Mermaid tool's result goes to a file; read `.valid` with jq.

**Pass 6b, break-glass (BACKLOG items 6 and 28) DONE and user-verified
2026-10-28** (RETROSPECTIVE, two entries), merged to `main`: hold and
release, the audit rule, the alert, `as_admin`/`as_me`, the reader
(`reader_on`/`reader_off`, port 3300, read-only), and the person in each
run output's header line (Q208). Not run: the reader with the cluster
removed.

**Pass 6c, cold storage (BACKLOG item 7) DONE and user-verified
2026-10-28** (RETROSPECTIVE), merged to `main`. On local the cold log
store is `var/log-store/<env>/cold/`, OTLP JSON lines, one directory for
each node, read with `driver/lib/cold-records.jq` (RECOVERY.md, "The
cold records": the files' purposes and an incident example). Backups and
a restore drill went to item 9 (Q217). Argo CD after the hour: a reload
in a private window asked for no step (the user, 2026-10-28). That open
item is closed.

**▶ IN FLIGHT: item 13, the Argo CD upgrade and the sync switch**,
branch `item-13-argocd-upgrade`, both steps BUILT AND AGENT-TESTED
2026-10-29, the user's verification pending, not merged. Step 1: chart
10.11.6 = v3.5.6, CLI 3.5.6, Redis through Zot, NetworkPolicies on,
annotation tracking (UPGRADE.md). Step 2: `sync off` / `sync on
[confirm]` / `apply` (`driver/modes/sync.sh`, on `argocd app sync
--local` in core mode), `fast-mode.sh` gone, the kustomize Applications
have one `source:`, `release` and `sync on` share
`differences_from_git`; GLOSSARY "Sync switch", LOCAL.md "Sync off and
on", ADR-0025 amendment. Three findings from the live tests, all fixed:
Argo CD's local render edits the kustomization in place (apply works on
a copy); after a local sync Argo CD compares against what it last
synced, not git, so `sync on` diffs with --revision and syncs each
kustomize app from git; a field that only the working tree added (an
annotation) is no difference for Argo CD and stays (the auditors CRB
still has `brzl.dev/spike=item-13b`; harmless; a `down`/`up` clears it).
The user still runs `10-host.sh`. NEXT: the user reads LOCAL.md "Sync
off and on" and verifies; then RETROSPECTIVE, the merge to `main`, and
BACKLOG 35 (rename `hold`/`release`) or the next item.
