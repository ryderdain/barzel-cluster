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

**Live test, first attempt (2026-10-16, run 202610161814) found two
things.** (1) Step 1 as I wrote it cannot work: the live ApplicationSet
still has the `postgres` and `demo-app` elements and recreates the
Applications right after the delete; phase 30 then stops on its guard
(rc 3), but the cluster Secret already points at `pass-5d`, where their
paths are gone (ComparisonError), and the portal's new pod crash-loops
until `chofesh.chofesh.svc` exists. The retire order is: drop the elements
from the live ApplicationSet, delete the Applications, delete their
namespaces, then `up`. Document this (LOCAL.md, ADR-0025) after the test.
(2) The conductor scaled itself to zero in the middle of phase 40: the idle
timer counted only run-sheet starts, and phase 40's two 900 s waits exceed
the 1800 s limit. Fixed in `driver/conductor/conductor.yaml` (a running
sheet counts as activity); phase 25 re-applies it on the next `up`.

**Live test (user runs):**

1. The old Applications must go first, or phase 30 stops (`error 3`, the
   element guard): `kubectl -n argocd delete application demo-app postgres`
   (cascades: the Cluster and its PVC go), then
   `kubectl delete namespace demo cnpg-demo`.
2. `bash driver/driver.sh local up | bash driver/kiesei.sh` on branch
   `pass-5d`.
3. Open `https://local.barzel.sh/apps/chofesh/` and search. Argo CD shows
   `chofesh`.
4. Optional loop: `fast_on`, edit `../chofesh`, `apply`, `fast_off`.

**After verification:** RETROSPECTIVE entry, BACKLOG item 3 "done", merge
`pass-5d` to `main` (fast-forward), LLM-CONDUCT. Then **▶ NEXT: pass 6,
logs** (ADR-0027, spike on branch `spike-logs`).

**Facts to keep in mind:** phase 30 applies the ApplicationSet file, and
Argo CD does not follow it from git (BACKLOG 15). Purge an old store when
the `driver` policy changes. Checks run in kiesei (Linux, no `dig`, cannot see
macOS). kiesei mounts the repo and `BRZL_EXAMPLE_APP_SRC` at their host
paths. The example app's name lives in three places (env, element, nginx).
