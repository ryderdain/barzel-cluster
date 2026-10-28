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

**▶ IN FLIGHT: pass 6b, break-glass** (BACKLOG item 6), branch
`pass-6b-break-glass`. **Design done:** Q195 to Q204, all (a)
(notes/DECISIONS.md). Q194 became Q198. Q202: "never" for an agent means
"for now" (user). The docs are committed (`39dc20e`): BREAK-GLASS.md,
ADR-0037 and the matching parts, written by a Fable 5.1 subagent and
reviewed. The user will verify all docs again in a final pass. In this
pass: item 28 (the reader), the local shape of items 23 and 29. Item 13
is the first item after pass 6.

**Done at the start, user-verified:** the gate's fixes (`38b394d`), items
27 and 33 (RETROSPECTIVE, the entry that corrects the second addendum).
Argo CD's own hourly click is still not seen cleanly. The user watches a
private window.

**▶ NOW: step 1 built (`58d2d7c`), the live test is the user's.** Step 1
has `hold` and `release` (driver/modes/break-glass.sh). Outside a hold the
admins have `view` (`brzl-tier-admins-view`), and `hold` adds
`brzl-break-glass`. Phase 10 writes the audit rule into `apiserver/` from a
template. The alert `BrzlBreakGlassHeld` reads a kube-state-metrics metric
for bindings. Fast mode refuses during a hold. The shell has `as_admin`
and `as_me`.
The audit policy's path is set when the cluster is made: `down`, then
`up`. Tried before the test: 23 driver cases pass, both emitters ran
read-only against the live cluster, and `argocd app diff --core` works
against the v2.13 server. **Step 2:** the reader of the admin log store.

**Live test, 2026-10-28 (user): steps 1 to 5 pass, step 6 two faults.**
(1) The metric was missing: kube-state-metrics finds custom-resource
kinds only from CRDs and skipped ClusterRoleBinding without an error.
Fixed: the built-in collector, `kube_clusterrolebinding_created
{clusterrolebinding}`. (2) A 500 from the gate, then Grafana's own page
with an error: two sign-ins at once in one browser (an old Grafana tab).
The gate: one CSRF cookie per sign-in (fixed). Grafana: BACKLOG 34. (3)
Found on the way: oauth2-proxy logs all cookies of a callback without
its CSRF cookie; the collector now redacts the gate's cookie values
(tested with the collector image). Pushed during the hold, so `release`
can also list monitoring, oauth2-proxy and log-collector. Steps 7 to 9
next, then a short second hold for the metric.
