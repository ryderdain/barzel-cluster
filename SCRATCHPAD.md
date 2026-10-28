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

**Step 1 DONE and user-verified 2026-10-28** (RETROSPECTIVE): hold,
release, the audit rule, the alert (`kube_clusterrolebinding_created`),
`as_admin`/`as_me`, and the three fixes of the live test (`d8a5023`).
The kiesei guide now names `as_admin` and `as_me` (the user had missed
them; Q201).

**Step 2 built (`1c14f02`) and tested by the agent, 2026-10-28** (the
user was away and allowed it once). `reader_on` with the cluster up: the
note, then the address; Grafana returned the break-glass run outputs
(both holds, the refused release, both releases) and the scale record
at level Request; `reader_on` again replaced the reader; `reader_off`
removed both containers. Not run: the test with the cluster gone
(`down`). Not user-verified, so no RETROSPECTIVE entry yet. `reader_on`
prints its note on stderr only, so the note is not in `reader-on.out`.
`driver/modes/reader.sh`, `reader-loki.yaml` (querier alone, read-only
mount, query_store_only, deletion off, no scheduler ring),
`reader-datasources.yaml`; port 3300.

**Round 4 decided 2026-10-28** (Q206 to Q209, all (a)) and built: the
run-output header line gets `person=<account> person_verified=false`
(`run_output_header` in driver.sh; kiesei.sh passes `BRZL_HOST_USER`;
the host run sheets use `id -un`). The kubeconfig and `driver.token`
stay on local. Docs: ADR-0037 (new "As built" section), BREAK-GLASS,
SECURITY, LOCAL, the kiesei guide, BACKLOG 6, 23, 29.

**▶ NOW: the user's checks** (the reader, with `down` if wished; the new
header line after any phase). Then the RETROSPECTIVE entry for step 2 and
round 4, close pass 6b, merge to `main`. Then pass 6c, then item 13.
