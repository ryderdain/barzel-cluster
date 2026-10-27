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

**▶ NEXT:** the user picks the next BACKLOG item. Candidates: item 6
(pass 6b, break-glass; it carries the user's refresher on the admin
kubeconfig beside the sign-on one), or items 21 to 33 (an alert channel,
narrower `kubectl` roles, image integrity, the device code for a remote
shell, the "Grant Access" page on the hourly re-login).
