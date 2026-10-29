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

**▶ IN FLIGHT: item 13, the Argo CD upgrade**, branch
`item-13-argocd-upgrade`. Decided: Q218 (a) chart 10.11.6 = v3.5.6, CLI
3.5.6; Q220 (b) `down`/`up` only; Q221 (a) NetworkPolicies on; Q222 (a)
the item also replaces fast mode; Q223 (a) `sync off`/`sync on` are
driver verbs, `hold`/`release` build on them; Q224 (a) `apply` = `argocd
app diff --local` then `sync --local` in core mode, the six kustomize
apps go to a single `source:`; Q225 (a) `sync on` refuses while live
differs from git (`sync on confirm`); Q226 (a) `apply` with sync on
prints the diff and stops (code 2); Q227 (a) annotation tracking
(replaces Q219); Q228 (a) GLOSSARY: "Sync switch", no mode; Q229 (a)
spike, step 1 upgrade, step 2 verbs. The user (AFK): the agent runs this
item's `down`/`up` cycles and raises issues for confirmation. SPIKE DONE
2026-10-29: `argocd app diff --local` in core mode (CLI 3.4.3, kiesei)
rendered a working-tree change and showed it; client-side render
(kustomize in kiesei); `--server-side-generate` failed on the path and
is not needed. `sync --local` refuses `sources:` even with one element
(`HasMultipleSources` = len > 0). STEP 1 DONE 2026-10-29 (agent-run
`down`/`up`, rc 0: v3.5.6 everywhere, Redis through Zot, five
NetworkPolicies, annotation tracking, 16 apps Synced, core-mode diff ok;
UPGRADE.md has the record; the user still runs 10-host.sh). NEXT: step
2, the sync switch: ApplicationSet single `source:`,
`driver/modes/sync.sh` replaces `fast-mode.sh`, `hold`/`release` share
its diff check, tests, GLOSSARY/LOCAL/BREAK-GLASS/ADR-0025 amendment,
then `down`/`up` and an `apply` test.
