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
`pass-6b-break-glass`. Decided: Q195 to Q201, all (a) (notes/DECISIONS.md).
Q194 became Q198. Build note for Q198: a binding's roleRef cannot change,
so `hold` adds the binding `brzl-break-glass` and `release` deletes it;
the change of `brzl-tier-admins` to `view` in git needs a new name or a
replace. Round 3 is open: an agent's path, and the doctrine questions of
items 16c and 25. The docs of the working model are with a Fable 5.1
subagent (the user's request): SECURITY.md, RECOVERY.md, a new
`docs/BREAK-GLASS.md`, and SPEC, an ADR, GLOSSARY, README and
ARCHITECTURE to match. In this pass: item 28 (the reader), the local
shape of items 23 and 29. Item 13 is the first item after pass 6.

**Built at the start:** the gate's fixes (`38b394d`). Item 27 is
user-verified. Item 33 waits for the hour of step 5 (no failed refresh in
the gate's log, no sign-in).
nginx dropped the cookie that oauth2-proxy refreshed, so Dex refused the
old refresh token ("claimed twice") and the person signed in again about
every hour. That was the re-login of the second addendum, not Argo CD's
token. The "Grant Access" page came from `approval_prompt=force`. Item
27: a NetworkPolicy admits only the portal to oauth2-proxy. After the
user's test: a RETROSPECTIVE entry that corrects the second addendum.
