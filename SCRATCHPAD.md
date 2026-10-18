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

*(2026-10-18, fable. Pruned to the current state. The history is in git,
the plan in [BACKLOG.md](BACKLOG.md), the records in
[RETROSPECTIVE.md](RETROSPECTIVE.md).)*

**Pass 5d DONE and user-verified** (RETROSPECTIVE 2026-10-18), merged to
`main`. The example app is `tzvat/chofesh`, private, deployed from its own
repo and CI. Local follows its `main` through the SCM generator. The other
environments follow a release tag (ADR-0034, Q141–Q157). The cluster's
registration still names revision `pass-5d`; the next `up` on `main`
re-registers it (same content).

**Facts to keep in mind:** phase 30 applies the ApplicationSet file, and
Argo CD does not follow it from git (BACKLOG 15; retiring an Application is
a three-step procedure, LOCAL.md). The driver stops when a phase cannot be
emitted; the stream belongs in kiesei. `bao` in a run sheet is a call into
the store's container: files on stdin, never inside a pipeline that feeds
`kubectl`. The SCM generator polls GitHub every 5 min anonymously for the
list, with the App for a private repo. The access files are in
`var/access/github/tzvat/` (the store holds the values now). Checks run in
kiesei (Linux, no `dig`, cannot see macOS). The example app's name lives
in three places (env, element, nginx).

**▶ NEXT: pass 6, logs** (ADR-0027; the spike on branch `spike-logs`;
BACKLOG item 4). Start with a short design round that re-reads the ADR and
the spike. Open small items that fit any pass: 16a (the access flow), 16b
(kiesei conveniences, `argocd` core mode), 16c (manifests as files).
