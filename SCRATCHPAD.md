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

**Live test PASSED on 2026-10-18 for the first build** (run 202610161814,
phases 25–40). A curl search wrote 1 search, 3 results and 1 API call.
Then the user asked how a workload update arrives. The answer was "it does
not": the driver-built image had a fixed tag. The update path is rebuilt
(Q148–Q152, ADR-0034 amendment). chofesh moved to the `tzvat` org. Its CI
(`e7afdce`) publishes `ghcr.io/tzvat/chofesh:<sha8>` and `:main` on each
push to `main`, and `:vX.Y.Z` on a release tag. `make release` and `make
dev-image` exist. The platform's `chofesh` element sits in a nested matrix
with an SCM generator (org `tzvat`, repo `^chofesh$`, requeue 300 s). The
cluster label `brzl.dev/workload-follow` (`BRZL_WORKLOAD_FOLLOW=branch` on
local) picks `sha` as the revision and `short_sha` as the image tag. Phase
20 pushes only kiesei. The `example-app-image/-tag` annotations are gone.
Element lookups use `.. | select(has("appName"))` for the nested matrix.
Static checks passed: the yq lookups, the phase 20 and 30 emits, a server
dry-run of the ApplicationSet, the fast-mode render.

**Live test of the update path (user runs):**

1. Wait for the chofesh CI run, and check once that the package `chofesh`
   under `tzvat` is public.
2. `rm var/run/local/current/30-gitops.ok`, then `up` on `pass-5d`. Phase
   30 applies the new ApplicationSet. Within 5 min Argo CD shows `chofesh`
   at commit `e7afdce…` with the image `…/ghcr.io/tzvat/chofesh:e7afdce1`.
3. Push a one-word change to chofesh `main`. CI, then the generator, then
   Argo CD. The page shows it within about 10 min.
4. Fast mode: `make dev-image` in `../chofesh`, `apply`, look,
   `git checkout deploy/local`, `fast_off`.

**After verification:** RETROSPECTIVE entry, BACKLOG item 3 "done", merge
`pass-5d` to `main` (fast-forward), LLM-CONDUCT. Then **▶ NEXT: pass 6,
logs** (ADR-0027, spike on branch `spike-logs`).

**Facts to keep in mind:** phase 30 applies the ApplicationSet file, and
Argo CD does not follow it from git (BACKLOG 15). Purge an old store when
the `driver` policy changes. Checks run in kiesei (Linux, no `dig`, cannot see
macOS). kiesei mounts the repo and `BRZL_EXAMPLE_APP_SRC` at their host
paths. The example app's name lives in three places (env, element, nginx).
