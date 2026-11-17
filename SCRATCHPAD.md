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

*(2026-11-17. Pruned to the current state. The history is in git, the
plan in [BACKLOG.md](BACKLOG.md), the records in
[RETROSPECTIVE.md](RETROSPECTIVE.md).)*

**Reassessment, Phase 1.** Feature work is frozen. The plan is the doc
"barzel-cluster: reassessment plan (Pocock skills, adapted)". The
baseline is the tag `pre-reassessment` (`46dcb5b`). All work through
item 39, and item 36, is done and user-verified (RETROSPECTIVE). The
open items stay in BACKLOG. The reassessment ranks them (items 8 and 40,
and the user's second look at item 13).

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

**Facts from item 13:** `apply` = `argocd app diff/sync --local` in core
mode on a copy of the source tree (the local render edits kustomizations
in place); after a local sync Argo CD compares against what it last
synced, so `sync on` diffs with `--revision` and syncs the kustomize
apps from git; a field that only the tree added is no difference for
Argo CD.
