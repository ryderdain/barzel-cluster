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
**Item 38, environment names, IN PROGRESS** on the branch
`item-38-environment-names` (Q245–Q248 accepted; ADR-0039). Done: the
ADR, GLOSSARY, SPEC, every document. Waiting: the code part, a script in
the session scratchpad (`apply-38-code.sh`, dry-run in a clone, 39 tests
pass), held until the user's teardown/bootstrap cycle ends, because the
checks and `kiesei.sh` read the tree live. Open: Q249 (the transit key
is made at first start only, so `brzl-dev` fails the check on a kept
store), and the user's follow-up question on the key names and
`env/*.env`. Then the migration of `var/` (`migrate-38-var.sh`), a
teardown under the old names, a bootstrap under `dev`, the ADR's "As
built", BACKLOG 38, RETROSPECTIVE after the user verifies. **Then
BACKLOG 36** (one command per line): the rule goes into `ryderdain/bash`
STYLE §1.2 first (the user commits there), then the emitters here. The
user wants a second look at item 13 after the next passes.

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
