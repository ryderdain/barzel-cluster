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

*(2026-11-05, fable. Pruned to the current state. The history is in git,
the plan in [BACKLOG.md](BACKLOG.md), the records in
[RETROSPECTIVE.md](RETROSPECTIVE.md).)*

**Item 37, the driver grammar, DONE and user-verified 2026-11-05**
(RETROSPECTIVE), merged to `main`: `BRZL_ENV=<env> driver.sh <mode>
<verb>`, the modes `cluster`, `break-glass`, `audit`, the teardown guard
(`## ⚠ ##`, `sed 's/^## ⚠ ##//'` in the pipe), ADR-0038. Item 35 was
dropped. The item-35 branch (local and origin) is the user's to delete.
**Items 38 and 39 DONE and user-verified 2026-11-05** (RETROSPECTIVE),
merged to `main`: the environment `dev` on the substrate `local`
(`env/dev.env`, `substrates/local.sh`, `gitops/clusters/dev`, ADR-0039),
and the kiesei image as a `core` stage with one stage per substrate
(ADR-0040). The cluster is up, from zero, under the new names. BACKLOG
had its cleanup round: done items keep their number and one entry, the
June 2026 sections are condensed, and item 40 is new.
**Item 36 (one command per line) built 2026-11-05, not yet verified.**
The rule is in `ryderdain/bash` (`a5e8127` on the branch
`bash-doctrine`: STYLE §1.2, the bash-ops skill, `includes/error.sh`).
`error.sh` is re-vendored and the `UPSTREAM` pin is that commit. The
driver's per-phase run block and one line of phase 10 are split (Q251,
Q252). `UPSTREAM` says `branch=main` (the user merged and renamed the
branch, 2026-11-05). The user verifies at the next bootstrap.
`env/dev.env` is in sections (Q250, `48074d5`).
**Then: the user's choice.** Item 8 (`promote platform`), item 40
(`cluster teardown all`, the CA and hosts setup), or the user's second
look at item 13. The branches `item-35-rename-hold-release`,
`item-37-driver-grammar` and `item-38-environment-names` are merged or
dropped, and the user's to delete.

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

**Item 13, Argo CD v3.5 and the sync switch, DONE 2026-11-04,
user-accepted** (RETROSPECTIVE), merged to `main`. The user looks at it
again after the next pass(es). Facts to keep: `apply` = `argocd app
diff/sync --local` in core mode on a copy of the source tree (the local
render edits kustomizations in place); after a local sync Argo CD
compares against what it last synced, so `sync on` diffs with
`--revision` and syncs the kustomize apps from git; a field that only
the tree added is no difference for Argo CD. The auditors binding still
has `brzl.dev/spike=item-13b` until the next `down`/`up`. Docker was not
running on 2026-11-04.

**▶ NEXT:** the user chooses: BACKLOG 35 (rename `hold`/`release`), 36
(one command per line, the rule in `ryderdain/bash` first, by the user),
or item 8 (`promote platform`).
