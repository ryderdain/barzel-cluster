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

*(2026-10-16, fable. Pruned to the current state. The history is in git,
the plan in [BACKLOG.md](BACKLOG.md), the records in
[RETROSPECTIVE.md](RETROSPECTIVE.md).)*

**Pass 5d BUILT, live test pending** (branch `pass-5d`, chofesh `main` at
`c9acf6a`, pushed). Decisions Q141–Q147 are in BACKLOG item 3 and ADR-0034
"As built". What changed in chofesh: `serve`, a Dockerfile,
`deploy/{base,local,aws}`. What changed here: the `chofesh` ApplicationSet
element with its own `repo` and `revision`, and `BRZL_EXAMPLE_APP_{NAME,SRC,TAG}`.
Phase 20 builds from `../chofesh`. Phase 30 writes
`brzl.dev/example-app-image/-tag` and checks that the element exists. Phase
40 checks `chofesh/pg`, `deploy/chofesh` and `/apps/chofesh/`. kiesei mounts
the checkout, and fast mode renders it. The portal passes `/apps/chofesh/`
with no rewrite. The demo-app and postgres bases and overlays are deleted. Static
checks passed: go test, the image build, the kustomize renders, nginx -t,
the phase emits in kiesei, the fast-mode render.

**Live test PASSED (2026-10-18, run 202610161814, phases 25–40 again).**
Phase 40: all eight Applications Synced and Healthy, the portal passes
`/argocd/` and `/apps/chofesh/`. I then ran one search through the portal
with curl: 200, three hits, and Postgres holds 1 search, 3 results, 1 API
call. Two attempts failed before that; the incident is written up in
BACKLOG item 15 (the orphan guard, the `.ok` of phase 30, the conductor's
idle timer), with the fixes `5e1c69f` and `a3b2f42` and the retire
procedure in LOCAL.md and ADR-0025.

**After verification:** RETROSPECTIVE entry, BACKLOG item 3 "done", merge
`pass-5d` to `main` (fast-forward), LLM-CONDUCT. Then **▶ NEXT: pass 6,
logs** (ADR-0027, spike on branch `spike-logs`).

**Facts to keep in mind:** phase 30 applies the ApplicationSet file, and
Argo CD does not follow it from git (BACKLOG 15). Purge an old store when
the `driver` policy changes. Checks run in kiesei (Linux, no `dig`, cannot see
macOS). kiesei mounts the repo and `BRZL_EXAMPLE_APP_SRC` at their host
paths. The example app's name lives in three places (env, element, nginx).
