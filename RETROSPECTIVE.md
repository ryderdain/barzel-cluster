# RETROSPECTIVE — episodic record (append-only)

The durable, self-referential record of **completed, fully-validated,
user-verified** work. Think episodic/declarative memory, in contrast to the
working memory in [SCRATCHPAD.md](SCRATCHPAD.md) and the agent's internal
MEMORY index — this file is the more expansive source of truth.

**Contract:**
- An entry is written only when the work is done, validated, and the user has
  verified it. Plans live in [BACKLOG.md](BACKLOG.md); in-flight notes in
  [SCRATCHPAD.md](SCRATCHPAD.md).
- Entries carry a timestamp and are **append-only**: a record, once set, is
  never changed. Corrections and follow-ups are NEW entries that reference the
  old one — later memories may reference, expand on, or supersede earlier ones,
  additively.
- Reference entries by their timestamp heading.

---

## 2026-06-10 — Founding record: inherited ground truth

This repository is the post-delivery snapshot of a Lead Infrastructure Engineer
take-home, repurposed as its own project. Verified state at founding:

- **Platform proven end-to-end on AWS, twice over:** dev (public-subnet model)
  validated 2026-06-04 and again from-zero 2026-06-09; **prod (private-subnet
  nodes, NLB-only ingress, ADR-0019) built and validated live 2026-06-10** —
  7/7 ArgoCD apps Synced/Healthy including monitoring, demo-app served through
  the Terraform NLB.
- **Operator lifecycle proven:** CNPG failover drill (2026-06-04, zero data
  loss) and the full DR restore drill (2026-06-08: total teardown → fresh stack
  → restore from S3 alone → exact acceptance counts 4/84/423/84), both
  conductor-driven.
- **Account torn to zero** 2026-06-10 (third full retirement); every teardown
  snag is procedure in `docs/TEARDOWN.md` (§3a manual finishers).
- **Migration:** all `enclv` naming → `brzl`; vendor references removed; the
  external notes folded in as `notes/`; ArgoCD manifests point at this repo
  (`ryderdain/barzel-cluster`). The new `brzl-*` resource names take effect on
  the next from-zero bring-up. The ArgoCD deploy key's public half still needs
  registering on this repo before any GitOps bring-up.
- The take-home's hiccup ledger (13 entries, with fixes and doc destinations)
  is preserved at `notes/PROD_RUN_REPORT.md`; the delivery-day session log is
  the final entry of `notes/LLM-CONDUCT.md`.

## 2026-06-12 — Consolidation daemon: §8 milestone, first gated admission

The full §7 steps 0–4 loop ran end to end and the user-as-arbiter issued the
first verdict. Verified state:

- **Vault live** (`aroni`, standalone repo): four passes landed via the
  scratch-worktree → ff-only mechanism (000 mechanics probe, 001 ingest,
  002 claim remap, 003 admission), each one atomic commit, pushed.
- **Ingest (§7.1):** `daemon/ingest_adapter.py` — 14 episode records (13
  hiccups, 1 retrospective), stable content-hash ids, idempotent (zero diff
  on re-run); surprise histogram {0:1, 2:10, 3:3}, masked failures
  auto-escalated. User decision folded in: `claim` = root-cause
  generalization (pass-002, no id churn).
- **Bundler (§7.2):** deterministic entity-rule clustering; 4 eligible
  bundles; known v1 noise (keyword match pulled the retrospective record
  into `argo_sync_ops`).
- **Gate (§7.3) + arbiter (§7.4):** cand-001 ("a success signal that does
  not assert the outcome is not evidence of success", children h5/h9/h12)
  scored lift +0.33 over 0.25 baseline (ordinal, self-judged per spec
  caveat), survived falsification after one boundary narrowing, and was
  **accepted** by the arbiter (bare accept; rationale recorded as none
  given). Admitted to `aroni/notes/` with provenance; decision in
  `aroni/decisions/pass-003.md`. cand-002 (env-coupling) drafted, queued.

## 2026-06-12 — Daemon operational: §7.5/§7.6 built, second admission (critic-narrowed)

- **§7.5 `vault_check.py`** (postcondition asserts: frontmatter, child links,
  supersession, decision pairing) and **§7.6 `scheduler.py`** (consumption
  derived from active notes — no state file) built and run clean; bundler's
  retrospective-record noise fixed (failure rules → `source=hiccup` only).
- **cand-002 admitted** (pass-004, the first vault_check-gated land): lift
  +0.25 over a 0.44 baseline. The gate's falsification seat **landed a hit on
  a child** — h2 was pre-empted at review, contradicting the draft's
  "runtime, serially" — and the claim was narrowed (audited→review /
  unaudited→runtime) before admission. Arbiter accepted the narrowed form
  with rationale: "the reasoning is sound" — the decision log's first real
  rationale.
- Queue after consumption: doc_drift (4 pending, priority 8) is the next
  drafting cycle; argo_sync_ops fell ineligible (2 pending).

## 2026-06-14 — aroni method formalized; doc_drift cycle (first revise verdict)

- **Method formalized** (user-directed, barzel `a92b712`): keyword **aroni**
  anchored in CLAUDE.md (vault + method); the repeated cycle codified as
  `daemon/ARONI_METHOD.md`. Two refinements: (1) candidates are surfaced in the
  vault (`aroni/_candidates/`, note + `.gate.md`) for the arbiter to read in
  Obsidian, never buried in chat; (2) verdict rationale is required for
  reject/revise + non-obvious accepts, **optional on a face-valid accept**
  (deferred refinement is the method, not a debt). New trays `_candidates/` +
  `gate_runs/` established (pass-005).
- **cand-003 admitted, REVISED** (pass-006 — first `revise` verdict, first
  substantive decision-log rationale). Gate ejected h3 (config fix-propagation,
  not doc rot; seeded forward) → narrowed to h1/h4/h8, lift +0.30. The claim was
  *face-valid* on rarity/time; the arbiter used the rationale-optional latitude
  to **sharpen causation** — rot is determined by **drift from
  last-validated conditions** (substrate + assumed use-context), not rarity (a
  non-causal correlate). h8 strengthened, h1 held, h4 retained via the
  context-drift dimension (boundary, confidence 0.65).
- **Corpus state:** 3 active notes (cand-001/002/003) consume 10 of 13 hiccups.
  Remaining 3 sit in now-ineligible bundles: h3 (seeded "fix doesn't propagate
  across parallel surfaces"), h11 + h13 (argo_sync_ops, 2 < the 3-child floor).
  The 13-hiccup fixture corpus is effectively exhausted; further consolidation
  awaits new episodes (or a second-order pass over the notes themselves).

## 2026-06-14 (later) — aroni made durable across sessions + portable across projects

- **Survival hooks** (user-directed): barzel `.claude/settings.json` gained a
  SessionStart hook that injects the SCRATCHPAD current-focus + the vault's last
  passes into every session (so state survives compaction and prose-compliance
  decay), and a PreCompact flush nudge. The store always survived (git); this
  makes the *practice* survive — and surfaces state to the human, whose cheap
  re-invocation is the real durability, not agent diligence.
- **aroni is now self-contained + shared.** The `daemon/` (tools + specs) moved
  out of barzel into the aroni repo (`tools/`, `SPEC.md`, `METHOD.md`); barzel is
  demoted to one *episode source*. One vault shared across all projects (universal
  beliefs transfer; per-project vaults rejected). Notes carry `scope:`
  (universal | project:<name>). Historical cand-001/002 gate runs + drafts folded
  into `aroni/gate_runs/` (pass-007), note provenance repointed in-vault.
- **Portability is one idempotent command.** `aroni/tools/init_project.py <repo>`
  installs the hooks (how they *travel*), scaffolds RETROSPECTIVE/SCRATCHPAD/BACKLOG,
  and emits the CLAUDE.md anchor; `aroni/ADOPTING.md` covers other repos *and* other
  domains (the method is domain-agnostic; only ingest is domain-coupled). ingest is
  now source-path explicit (retro-only path works for non-infra domains). A signature
  bug (PreCompact duplicated on re-run) was caught by dogfooding and fixed; hook
  strings are ASCII so machine-written settings.json is byte-stable.
- **Tabled** (BACKLOG): aroni `lift` is ordinal + judge-relative — not comparable
  across passes by different models without a single-judge re-gate.
- Commits: barzel `a92b712`→hooks/anchor; aroni `17e67a0` (self-contained move),
  `892aba4` (pass-007 provenance + scope). Consolidation state otherwise unchanged
  (3 notes, corpus bundle-exhausted).

## 2026-06-14 (late) — aroni's second order: doctrine, instruments, and a closed loop

The self-referential arc — the vault consolidating its own construction, and
growing a structure. All arbiter-verified in-session.

- **cand-004 (SSOT) admitted** (pass-011): an uncoupled redundant copy of a
  single-source fact diverges/drifts/is-lost. Reached the ≥3 floor by promoting a
  real take-home episode (derive-don't-store); the arbiter ruled the predicate
  broadening *correct generalization*, not a reach.
- **Subordination doctrine** (METHOD): when claims overlap, generate a higher-order
  claim that subordinates them (overlaps + distinctions explicit); narrowing is
  **failure-driven**, never preemptive; the aim is claims that re-bundle by point of
  contact so the model self-selects experience-laden context.
- **cand-005 "context-seam"** — the first **second-order** note (children are notes).
  "A property true in one context breaks on contact with a second; the bug lives in
  the *relation*, invisible from either side → instrument the seam, don't fortify the
  source." Made falsifiable by **the seam test** (a one-question seam/source
  classifier).
- **The second-order gate**, accepted after a deep `lift` explanation: lift is a
  *first-order* instrument (it makes concrete episodes mutually predictable); over
  claims it's a plausibility vibe → **demoted to a sanity check**. Second-order
  admission = (seam-boundary) AND (≥1 **demonstrated intersection** — an episode that
  is a child of ≥2 subordinates). Instrumented by `tools/intersections.py`.
- **cand-005 is HELD**: the intersection instrument finds **zero** co-firings, so its
  asserted intersections (h11=002∩004 — even excluded by cand-002's boundary) don't
  count. The instrument caught its author's over-reach on first use — the system
  holding its own builder to the standard.
- **Co-fire re-evaluation** (the user's instinct, verified + mechanised): a shared new
  child makes subordinates' lift stale → re-gate; the direction (hold/rise=wire,
  drop=narrow, persistent=merge) is the Hebbian signal. **The loop is closed +
  enforced**: `vault_check` fails any pass that lands an unacknowledged co-firing;
  `intersections.py --work-order` emits the tasks. Code detects+enforces; the model
  judges. Verified by dogfooding.
- Vault at aroni `b5744e3`: 4 notes, 17 episodes, 5 decisions, passes 000–013.

## 2026-10-09 — local-first refactor, passes 0–2: the emit-style driver runs local

User-verified: the first live `driver.sh local` run on sleipnir (run
`202610091342`) brought up all three phases — `10-substrate`, `20-platform`,
`30-workloads` — each `rc=0` and `.ok`. The user's verdict: "worked like a charm";
running each phase script on its own as an emit script showed exactly what would
happen before it did.

- **Design** (grilling, 2026-10-07, Q1–Q53): local is the first environment of
  local → dev → prod; one operator image **kiesei** in two modes, **driver**
  (outside the cluster) and **conductor** (in it); `platform.sh` split into
  emit-style phase scripts and a thin driver; Zot/OpenBao local stand-ins.
  ADRs 0021–0024; vocabulary in `GLOSSARY.md`.
- **Pass 0**: ADRs moved verbatim into `docs/adr/`, one file each.
- **Pass 1**: the bash doctrine moved to `ryderdain/bash` as the only home;
  `CLAUDE.md` now points there. The recurring `&&`-chaining was traced to this
  repo's own `CLAUDE.md`, loaded every session — removed.
- **Doctrine corrections from the user** (each one overturned an agent draft):
  `{ … }` groups are anonymous functions for the *reader*, not only an execution
  mechanism; a check goes only where re-running a block would harm; reuse the
  existing `error` function (code 3 = deliberate stop) instead of inventing
  `step_failed`; the driver is an emit script — **running its output is the
  approval**, never a prompt; script file names use hyphens, functions
  underscores.
- **Instruments caught real bugs before use**: a subagent probe found that an
  `exit` inside a piped group only ends the pipe (→ "never pipe a checked
  group"); `driver-cases.sh` found same-minute runs reusing old `.ok` files.
- **Also**: `notes/` made local-only and removed from the public tree;
  toolbox → kiesei and hyphenated script names across both repos.

## 2026-10-09 — local-first refactor, pass 3: Zot, kiesei driver, warm conductor

User-verified on sleipnir. Run `202610091438` (3a+3b) and run `202610091501`
(3c, `driver.sh local up | bash driver/kiesei.sh`): all five phases — `10-substrate`,
`15-conductor`, `20-platform`, `30-images`, `40-workloads` — `rc=0` and `.ok`.

- **3a — Zot outside k3d**: a persistent pull-through cache for docker.io,
  ghcr.io, quay.io, registry.k8s.io and oci.external-secrets.io, and the push
  registry for local images. The Zot catalog showed each upstream's namespace,
  so the k3s mirrors work. k3s pinned to `v1.31.5+k3s1` (parity with AWS).
- **3b — the driver runs from kiesei**: the only host prerequisite is a
  container engine; `| bash driver/kiesei.sh` runs the emitted stream in a kiesei
  container (host network, engine socket, repo at the same path). The API is
  pinned to `127.0.0.1:6550`, so one kubeconfig works on the host and in kiesei.
- **3c — the warm conductor**: phase `15-conductor` puts kiesei in the cluster;
  phases with locus conductor (`20-platform`, `40-workloads`) are copied into the
  pod, verified by checksum, run detached, followed, and their `.rc` collected.
  ESO's image came through Zot (`oci.external-secrets.io/…` in the catalog). The
  conductor scaled itself to zero after exactly 30 idle minutes.
- **A user question exposed a doc gap**: the phase table's "locus" column read
  as "which command to type". `docs/LOCAL.md` now says the locus is where the
  run-log runs and the command is always `driver.sh`.
- **Instruments caught bugs before the live run**: byte offsets (not
  characters) when following the conductor's log; an unquoted heredoc that would
  expand `$1`; ESO bypassing Zot through a fifth upstream.
- **Also**: a repo markdownlint config (no line-length check in tables); about
  600 older lint errors parked in `BACKLOG.md`.

## 2026-10-13 — local-first refactor, pass 4: Argo CD on local, fast mode

User-verified on sleipnir, run `202610131623` (branch `pass-4`, which Argo CD
followed): all six phases — `10-substrate`, `15-conductor`, `20-images`,
`25-bootstrap-secrets`, `30-gitops`, `40-workloads` — `.ok`; then fast mode:
`fast_on`, a working-tree change (demo-app replicas 2 → 5) live through
`apply` with only the Deployment OutOfSync, and `fast_off` back to the branch,
all Synced.

- **One platform ApplicationSet** for local, dev and prod (ADR-0025). The
  per-environment values are labels and annotations on the cluster Secret. An
  offline Go renderer (the controller's template engine) showed dev and prod
  get the same 7 Applications as the old per-env files; local gets 5, with
  every image through Zot (`localhost:5001/quay.io/...`, verified in the Zot
  catalog).
- **Design corrections from the user:** the shared ApplicationSet over a
  local copy (Q54); a golden render test on a disposable cluster rejected as
  extra manual steps for one purpose (→ a guard in the ApplicationSet and an
  orphan check in phase 30-gitops, Q63); the user's "fast mode" for
  emergencies was a different concept → **break-glass mode** (Q62/Q65,
  BACKLOG pass 6b); the repo made private → a deploy key now, a GitHub App
  before leaving local (Q61).
- **Live run found three fast-apply bugs** the offline checks did not: a
  forced namespace broke objects in another namespace; kubectl's merge removed
  Argo CD's tracking label; and the first label fix assumed the upstream key
  (`app.kubernetes.io/instance`) when the chart sets
  `argocd.argoproj.io/instance` — the user's manual Sync exposed it. The key is
  now read from `argocd-cm`. A failed apply now stops the stream.
- **Also:** Zot is replaced when its config changes (the pass-3 gap); the
  `public.ecr.aws` mirror; the legacy `--with-sso` overlay works again.

## 2026-10-13 — local-first refactor, pass 5: ESO 2.12, the external secret store

User-verified on sleipnir. 5a (run `202610131940`): ESO 0.10.7 → 2.12.0 on the
`v1` API, all apps Synced/Healthy, `pg-app` projects `uri`. 5b (runs
`202610132037` then `202610132108`, branch `pass-5b`): six Applications
Synced/Healthy including `secret-store`; `brzl-secrets` "store validated"; the
smoke value written by phase 25 came back through ESO (hashes equal); then
`down` and `up` **with no deploy key given** — phase 25 found the key in the
store, the store unsealed on its own after the cluster was remade.

- **The user's correction set the design** (Q66): an in-cluster OpenBao was
  "not properly mimicking" Secrets Manager. The store now runs beside the
  cluster like Zot (ADR-0026): exists before it, outlives it, seeded once by
  the driver, read by ESO through Kubernetes auth against the cluster API from
  outside. The user also cut the phase list to five (Q69: 15-conductor folded
  into 20-images and 25-bootstrap; the smoke test lives in phases 25 and 40,
  no phase of its own) and asked for the ESO upgrade first (Q76).
- **Research before building** (two subagents, primary sources): OpenBao 2.7
  removed `file` storage (→ `pebbledb`); the static seal is built in; self-init
  cannot return a token and has an open 2.7.1 defect (→ scripted init, root
  revoked); Kubernetes auth from outside needs host + CA + a reviewer token;
  ESO serves only `v1` since 0.17 and its images moved to ghcr.io.
- **Live run found a driver bug the offline checks could not**: the procedure
  arrives on stdin, and a `docker exec -i` with no piped data swallowed the
  rest of the stream — two runs ended silently after phase 10. Every run line
  now takes stdin from `/dev/null`; the mechanics test's fake phases read
  stdin, so the old driver fails 2 cases. Rule parked for the bash doctrine.
- **Also**: a `bao()` prelude at the top of a run-log, so lines read as plain
  procedure; ESO's `oci.external-secrets.io` mirror removed from Zot.

## 2026-10-15 — local-first refactor, pass 5c: the admin portal

User-verified on sleipnir (run `202610151255`, branch `pass-5c-portal`).
`https://local.barzel.sh/` opens with no certificate warning. Argo CD under
`/argocd/` logs in and lands on its applications page. The demo-app under
`/apps/demo-app/` runs a search and stores it. `bash driver/kiesei.sh
shell` gives `argocd login` through the portal. Phase 40's check proves the
chain from the driver: `200` from the page and from `/argocd/`, through the
store's CA.

- **The design round (Q126–Q140) changed the first plan twice**, both times
  from the user. A driver-run `renew` suited only a local cluster (Q130).
  So cert-manager renews on every substrate, and the TLS mode is a
  `ClusterIssuer` for each environment (ADR-0036). A person must be able to
  try the platform with nothing public (Q134). So a `.localhost` name is
  the default, and the DNS stand-in serves only a chosen name (Q140). The
  user also asked for the guidebook (`docs/guide/`, one draft when a tool
  arrives: Kustomize, cert-manager, kiesei), for operator steps that stand
  out (the boxed block, for the driver machine's OS), and for a flat host
  name (Q137: password managers fail on `sub.sub.domain.tld`).
- **Live runs found four things the static checks could not.** The deploy
  key must prefix the right side of the pipe (the agent's own command was
  wrong). The OpenBao role signs EC keys only, and cert-manager made RSA:
  one line in the `Certificate`, after which cert-manager backs off for an
  hour. The checks run in kiesei, which has no `dig` and cannot see macOS.
  They now verify what they can and print the rest. Argo CD v2.13's UI
  doubles its base path in the login `return_url`: one nginx redirect, to be
  removed with the Argo CD upgrade (BACKLOG).
- **Facts established for later.** macOS resolves every `*.localhost` name
  to `127.0.0.1` at the system level. Docker Desktop lets a container use
  the Mac's `/etc/resolver` entries. glibc in the container does not resolve
  `*.localhost`, so `kiesei.sh` maps the portal host itself and mounts the
  CA into the container's trust store.
- **Also:** k3s runs without Traefik and its service load balancer. The
  `driver` policy of an existing store had to be remade once (purge).

## 2026-10-15 — pass 5c follow-up: the `*.localhost` default, Argo CD v2.13.4

User-verified on sleipnir. With the CA trust and the resolver file removed
and `BRZL_PORTAL_HOST=brzl-local.localhost`, `up` printed no DNS step, the
portal opened (with the expected certificate warning, the CA untrusted),
and the login worked. Argo CD chart 7.7.23 (v2.13.4) fixed the login
`return_url` under a base href. The nginx redirect, which never caught a
client-side route change, is gone. Then back to `local.barzel.sh` with the
two printed one-time steps: no warning.

- **Found:** phase 30 applies the ApplicationSet file, and Argo CD does not
  follow it from git. So the chart bump reached the cluster only on the
  next `up` (BACKLOG item 15, for pass 7).

## 2026-10-18 — local-first refactor, pass 5d: the example app is chofesh, private, from its own repo

User-verified on sleipnir, four live tests. The platform ships no workload
any more. `apps/demo-app`, the demo-app and postgres GitOps bases and their
local overlays are gone. The example app is `tzvat/chofesh`, a private
repository under a GitHub organization. It has `chofesh serve` (the
demo-app's page and search, `/healthz`, `/readyz`, `/metrics`), a
Dockerfile, its own CI, and `deploy/{base,local,aws}` with its CNPG Cluster
in its own namespace. The credential stays CNPG's, read directly. The
portal passes `/apps/chofesh/` with no rewrite
([ADR-0034](docs/adr/0034-example-app-is-a-separate-workload.md),
Q141–Q157).

- **Test 1, bring-up.** All Applications Synced and Healthy. A search
  through the portal wrote 1 search, 3 results and 1 API call into the
  app's Postgres. The data survived every later `up`.
- **Test 2, the private path.** Argo CD read the private repo with the
  GitHub App. The SCM generator followed `main`. Zot pulled the private
  package with the `read:packages` token. The access script made the
  credentials in six steps (App `brzl-reader-tzvat`, one installation on
  `tzvat`), and phase 25 seeded the store from its files.
- **Test 3, a push to `main`, no driver action.** CI published in 441 s.
  The ApplicationSet followed the commit at once. The rollout was done at
  467 s, and the page's new footer named the commit. About eight minutes
  from push to page.
- **Test 4, fast mode.** `make dev-image` built into Zot's push namespace
  and pointed `deploy/local` at the build. `apply` rolled the Deployment to
  it (the footer showed `c9f3ddb-da39a3ee`). `git checkout deploy/local`
  and `fast_off` brought the branch's build back.
- **Found, the design.** The first build let the driver build the image
  with a fixed tag, so a code change never arrived (Q148). The fix is the
  follow policy. The driver is out of the workload's path. An environment
  follows a branch (local, through an SCM generator) or a release. Two
  GitHub facts shaped it. The container registry accepts only a classic
  token. The SCM generator lists an organization, not a user (`ryderdain`
  answered 404), so chofesh moved to `tzvat`.
- **Found, the driver.** The orphan guard works, but removing an
  Application is a three-step procedure (BACKLOG 15, LOCAL.md "Retire an
  Application"). The check of phase 30 earned an `.ok` from a sheet that
  stopped at the guard. Fixed: it compares the live elements with the
  file. The driver ran an empty run sheet when a phase could not be
  emitted on a host without `yq`. Fixed: `error 3`. The conductor's idle
  timer cut a 30-minute phase. Fixed: a running sheet counts as activity.
  `bao` in a run sheet runs in the store's container, so files go on
  stdin, and a `bao` call inside a pipeline swallows the pipe. Both fixed.
  The AppProjects still named `ryderdain` after the move. Fixed.
- **Carried.** The access flow is clunky (BACKLOG 16a). The operator's
  small annoyances in kiesei, with core mode as the tested way for
  `argocd` (16b). Manifests as files in the run directory (16c). The AWS
  side of ADR-0034, ECR pull-through for `ghcr.io` with a credential
  (pass 8). `deploy/aws` is untested until pass 9.

## 2026-10-21 — local-first refactor, pass 6: logs, metrics and Grafana on every substrate

User-verified on sleipnir. The design round Q158–Q162 amended ADR-0027.
kube-prometheus-stack runs on every substrate, and its Grafana is the one
viewer. Loki and the collector come from Helm charts. A collector beside
the cluster sends the run outputs and the secret store's audit log to the
collector in the cluster. It queues them on disk while there is no
cluster. BACKLOG gained 17 (`state`), 18 (a separate purge) and 19 (a
low-memory mode).

- **Bring-up.** `down` and `up` made the cluster again with the API audit
  policy, the k3s log file and the admin data's mount. All Applications
  were Synced and Healthy. Phase 40 found records from every admin source
  (run outputs, k3s server, API audit, OpenBao audit, events) and the
  example app's logs in the diagnostic store.
- **Grafana.** The user queried both stores in Explore. A search on the
  app's page appeared in the diagnostic store within the last hour.
- **The admin data outlives the cluster.** After a second `down`,
  `var/log-store/local/admin/` still held the chunks and the daily index
  files.
- **Memory.** The full environment used 5.0 GiB, the k3d node 4.7 GiB of
  it (estimate 5.5 GiB). Recorded in LOCAL.md.
- **Found before the live test, by rendering.** The chart templated the
  ExternalSecret's `{{ .password }}` away. The two Loki installations
  collided on ConfigMap and Service names. Loki's image helper dropped the
  registry from a path whose first part has a dot. A Loki container with
  the chart's config was ready after about 45 s, so the spike's readiness
  problem came from its own in-memory ring. Q162's port mapping was not
  needed, because the collector chart opens host ports on the node.
- **Found in the live test.** Explore said "origin not allowed". The
  portal's `/grafana/` location set its own proxy headers, so nginx
  inherited none from the server level, and Grafana got the Service's name
  as `Host`. Fixed: every proxy header is at the server level. Phase 40
  now logs in and queries Grafana as a browser does. It reproduced the
  fault before the fix and passed after it, with no driver action.
- **Open** (ADR-0027 "Open after pass 6"). The collector's OTLP receiver
  has no credential. On a cluster with more nodes, each event arrives once
  from each node. The AWS parts wait for pass 8.

## 2026-10-22 — item 4a: mutual TLS on the OTLP receiver

User-verified on sleipnir. The in-cluster collector accepted OTLP from
anything that reached it. Now it accepts only the client certificate of the
collector beside the cluster (Q163–Q166, ADR-0027 and ADR-0036 amendments).
The store's CA is made in phase 10. The client-only PKI role `log-shipper`
issues that certificate on every run, valid for 30 days. cert-manager gives
the receiver its server certificate, `log-intake.<host>`, through the
portal's issuer. The PKI role `portal` signs server certificates only.
gRPC is closed. GLOSSARY gained "Roles", the five meanings of "role" and
the roles themselves. Every platform record now names the node of its
collector, so copies of an event from several nodes are distinguishable.

- **Bring-up.** A fresh `up`. Phase 40 found records from every admin
  source. The run outputs and the OpenBao audit log arrive only through
  the mutual TLS, so the path works.
- **Refused.** A client on the cluster's network with no certificate got
  no answer (curl exit 56).
- **The portal's certificate** carries only TLS Web Server Authentication.
- **Before the live test.** A throwaway pair with the real shipper config
  delivered. It refused a client with no certificate, a server-only
  certificate from the same CA and a foreign CA. A throwaway OpenBao
  accepted both roles and refused another name.
- **Found in the live test, not caused by 4a.** Pod lookups of public
  names failed in bursts from 11:05 to 12:47 UTC. The node
  resolved them. `monitoring` used its five sync retries and stopped, so
  phase 40 waited. A hard refresh and one sync fixed it in about a minute.
  BACKLOG 20 parks the retry limit for a decision.

## 2026-10-22 — BACKLOG 20: sync retries with no limit, and an alert

User-verified on sleipnir. After the DNS incident of item 4a, a failed
sync is retried with no limit (Q167). Phase 40 names an Application that
is not Synced and failed 3 times or more, with its error. The alert
`BrzlSyncFailing` fires at 3 failed attempts (warning) and 5 (critical)
(Q168, ADR-0025 amendment). kube-state-metrics reads each Application's
retry count, phase and sync status. No Alertmanager runs, so the alert
shows only in Grafana and Prometheus (BACKLOG 21: a channel).

- **Checks.** The `monitoring` Application has `retry.limit: -1`. Grafana
  lists `BrzlSyncFailing` twice, as Normal. Prometheus holds one series of
  `brzl_argocd_app_sync_retries` for each of the 12 Applications. A
  stacked graph shows only the five that are not 0, which looked like
  missing series.
- **Found before the live test.** kube-state-metrics, run read-only
  against the cluster, showed the stale record of `monitoring` from the
  incident: Failed, 5 retries, but Synced. So the alert counts only an
  Application that is not Synced. Prometheus's rule tests confirmed it:
  the stale record stays quiet, a failing sync warns at 3 and goes
  critical at 5, and a recovered one stays quiet.
- **Found in the live test, a race in the conductor.** After 30 minutes
  idle, the conductor scaled itself to zero. That was the same second in
  which `conductor.sh` woke it for phase 30. `conductor.sh` chose the
  terminating pod and then reattached to it for up to an hour. Fixed: it
  claims a Ready pod that is not terminating and resets its idle timer.
  It stops with a message when the pod is gone.

## 2026-10-23 — pass 6a, step 1: web sign-on

User-verified on sleipnir. Every environment has sign-on in front of the
admin portal (ADR-0035 amendment, Q169–Q185). Dex is the OIDC issuer at
`/dex/`, with GitHub as the identity provider and one OAuth App for each
environment. nginx asks oauth2-proxy about each request. Argo CD and
Grafana are clients of Dex, and their built-in logins are off. Three
access tiers are three GitHub teams. The workloads are outside sign-on.
Phase 10 writes a host run sheet for the steps on the operator's machine,
and `driver/kiesei.sh` runs it on the host (Q180). The legacy `--with-sso`
path is removed.

- **Checks.** The teams and the OAuth App were made with
  `driver/access/github.sh`. After a new `up`, phase 40 passed. In the
  browser, GitHub's approval led to the portal page. Argo CD's "Log in via
  GitHub" gave the admin tier, and Grafana signed in as Admin. The example
  app opened without sign-in in a private window. The host run sheet
  reported its steps done.
- **Sign-out.** Grafana's and the portal's "Sign out" sign the person in
  again at once, because GitHub keeps its own session. Kept as it is for
  now (Q185, BACKLOG 26).
- **Found in the live test, each fixed and pushed:**
  - The Dex image names its user, not its number, so the kubelet could
    not verify `runAsNonRoot`. Then Dex needed a writable `/tmp` for its
    expanded config.
  - On a new cluster, the `grafana-admin` ExternalSecret failed while the
    External Secrets webhook was not ready. The sync then waited for
    Grafana without end. The ExternalSecret now has its own sync wave.
  - An interrupted driver left phase 40 running in the conductor. The
    next run started a second run, and the first run's exit status was
    taken as the second's. `conductor.sh` now follows a run that still
    runs, and never starts a second.
  - nginx made the redirect to sign in absolute, with its container port
    8443. Its redirects are relative now.
  - argocd-server reads the Secrets that `oidc.config` names only when it
    starts, and it started before External Secrets made the Secret. Its
    settings API showed the right issuer, so phase 40 passed, but the
    sign-in failed. Phase 25 now writes that Secret from the store and
    restarts argocd-server when it changes. Phase 40 checks the order.

## 2026-10-27 — pass 6a, step 2: `kubectl` through Dex

User-verified on sleipnir: `kubectl auth whoami` with the sign-on
kubeconfig answers `oidc:ryderdain`, with the group
`oidc:tzvat:brzl-admins`, from the cached token and without a browser
step. The design is Q186–Q192 with the conditions of an outside security
review (ADR-0035, "As built", step 2). The kube-API trusts Dex through a
structured `AuthenticationConfiguration` that phase 10 writes and the
node mounts, and the API server reads again when it changes. Phase 10
also writes `kubeconfig-sign-on` (no secret), whose user runs kubelogin,
pinned in kiesei. The portal has a fixed Service address on local. The
tiers' bindings are in `gitops/clusters/<env>/access/`. Dex's ID tokens
last 1 hour and its refresh tokens 7 days. The gate and Grafana refresh
every hour, so a removed person loses access within the hour. A
NetworkPolicy admits only the collector, Grafana and itself to the admin
log store. Phase 40 checks the parts: PKCE, the portal's address, the
tiers' rights by impersonation, the policy.

- **Checks.** Phase 40 passed on a new cluster, with the user running
  phase 10 twice to confirm idempotency. The kube-API named the person.
  SECURITY.md and SECRETS.md carry the review's findings (the four roots
  of trust, the flows by scenario, sessions and revocation, the per-root
  tables).
- **Not yet run when this was written.** The `up` with the durable hosts
  script (the user's next step). The audit log read in Grafana. The
  hourly re-login in Argo CD. The merge to `main`. SCRATCHPAD holds them.
- **Found in the live test, each fixed and pushed:**
  - `ca.crt` has no newline at its end. So `sed` ran the certificate's
    last line into the next heredoc, the API server refused the file,
    and `k3d cluster create` waited without end. `awk` writes it now,
    and phase 10's check parses the file.
  - The substrate check looked for the host alias in CoreDNS before k3d
    and k3s settled it (gone with the next item).
  - The `v1` exec API requires `interactiveMode`. Phase 10 sets `Never`,
    as kubelogin's own setup does.
  - Docker Desktop's "Enable host networking" was off, so no callback
    from a container could reach the browser. A probe listener proved it
    for `0.0.0.0` and `127.0.0.1` alike. With it on, both reach the Mac.
    LOCAL.md names the setting and the symptom. A wrapper added on a
    wrong guess (only `0.0.0.0` forwarded) was reverted.
  - A Docker Desktop restart dropped both lines of k3d's `--host-alias`
    (the node's `/etc/hosts` and CoreDNS's NodeHosts), so the API server
    resolved the issuer to `127.0.0.1` and refused a correct token. The
    node now runs a k3d entrypoint script at every start, and the pods
    keep step 1's CoreDNS rule: two mechanisms, against Q186's one,
    recorded in the ADR.
- **Decided on the way.** Q191 (a): 1-hour ID tokens, so Argo CD's UI
  asks for a click every hour. Q192 (a): the sign-in stays in kiesei. A
  remote shell gets the device code later (BACKLOG 32). The user's
  side-channel question moved the fixed address into the local overlay,
  with the range explained.

## 2026-10-27 — pass 6a, step 2, addendum: the kiesei shell and the CLI path

User-verified on sleipnir, after the entry above. The durable `up` (the
node's hosts script, the CoreDNS rule) passed its checks, and the sign-in
again. The kiesei shell makes the person the default (Q193):
`driver/lib/kiesei-shell.sh` sets the sign-on kubeconfig and signs in at
its start. It gives `argocd` a helper that signs in on first use, with
its session in the run directory. `argocd app list` from the shell
printed the applications through the gate.

- **Found in the live test, each fixed and pushed.** Three faults in step
  1's CLI path, which step 1's test had not covered. The CLI reads Argo
  CD's settings over gRPC-web, not REST, so that path had to be outside
  the gate too. Its service is `cluster.SettingsService` (argocd-server:
  "unknown service"). The CLI sends its token in a header named `token`,
  not as a bearer, so the gate ignored it. nginx now maps that header to
  the bearer for the gate's subrequest.
- **Docker Desktop.** "Enable host networking" must be on for any
  callback to reach the browser (LOCAL.md).
- **Not yet run:** the audit log read in Grafana, the hourly re-login in
  Argo CD, the merge to `main`.

## 2026-10-27 — pass 6a, step 2, second addendum: the last checks, the merge

User-verified on sleipnir, after the entries above. The two checks that
the first addendum listed as not yet run passed. Pass 6a is done: web
sign-on, `kubectl` through Dex, the kiesei shell, the Argo CD CLI through
the gate, and the auth flows as six diagrams in SECURITY.md. Merged to
`main`.

- **The audit log names the person.** The user ran `kubectl get nodes`
  from the kiesei shell. In Grafana (Explore, the data source "Admin log
  store"), the query
  `{brzl_store="admin-log-store", brzl_source="api-audit"} |= "oidc:ryderdain"`
  returned its records.
  The same query through the API server's proxy to the store, as phase
  40 runs it, returned one stream with several values.
- **The hourly click in Argo CD.** Argo CD was opened through the portal
  at 12:55 CET. A reload at 14:59 showed a "Grant Access" page, and one
  click restored the session, with no step at GitHub. The ID token lasted
  its hour (Q191), as designed. One open point: that page is Dex's
  approval page, and Dex's `skipApprovalScreen` is on, so the page was
  not expected. Which client asked, and why, is BACKLOG 33.

## 2026-10-27 — pass 6b start: the gate's two faults, and item 27

User-verified on sleipnir. **This entry corrects the second addendum
above:** the re-login at 14:59 CET was not Argo CD's 1-hour token. It was
a fault of the gate, and the "Grant Access" page was a second fault.

- **The gate lost its session about every hour.** The logs of oauth2-proxy
  and of Dex showed it. oauth2-proxy refreshed the session in its answer to
  nginx's subrequest, and nginx dropped the new cookie. The browser kept
  the old cookie, Dex refused its refresh token as "claimed twice", and
  the person signed in again. nginx now passes the cookie
  (`auth_request_set`, `add_header Set-Cookie`). The browser has one
  cookie, `_brzl_sign_on`. The gate's log shows a refresh at a session
  age of 1 h 5 min, with no failure. After the hour, the portal, Grafana
  and Argo CD asked for no sign-in.
- **The "Grant Access" page** came from oauth2-proxy's default
  `approval_prompt=force`, which Dex obeys although `skipApprovalScreen`
  is on. The gate sends `auto` now, and the page is gone (BACKLOG 33).
- **Item 27: only the portal reaches oauth2-proxy** (a NetworkPolicy from
  the chart). Phase 40 passed with its new check. A probe from a pod in
  another namespace was refused at once, because k3s rejects with
  `icmp-port-unreachable`, not by a timeout. The portal still reaches
  `/ping`.
- **Still not seen cleanly:** Argo CD's own request for a click after its
  1-hour token (Q191). The gate's fault hid it before. The user watches
  a private window for it.

## 2026-10-28 — pass 6b, step 1: break-glass hold and release

User-verified on sleipnir, on a new cluster (`down`, then `up`), at
`58d2d7c` and the fixes in `d8a5023`. Design: Q195 to Q204 (ADR-0037,
docs/BREAK-GLASS.md).

- **Outside a hold, the admins have `view`.** In the kiesei shell,
  `kubectl auth whoami` named the user through Dex, and
  `kubectl auth can-i create pods` said `no`. Phases 10 and 40 passed.
- **`hold` with a reason** wrote the record with the person from
  sign-on, turned auto-sync off and bound the admins to `cluster-admin`.
  `can-i` then said `yes`. A live change (`portal` at 2 replicas) stayed.
  Fast mode refused during the hold.
- **The audit rule** recorded the change at level `Request`, with
  `replicas: 2`, in the admin log store.
- **`release`** stopped with exit 3 and listed the differences.
  `release confirm` deleted the binding, turned auto-sync on, and printed
  the review queries. The portal went back to 1 replica, and `can-i` said
  `no` again. `as_admin` and `as_me` switched the shell's kubeconfig and
  prompt.
- **A second hold and a `release` with no differences** finished without
  `confirm`. During that hold, Prometheus had the series
  `kube_clusterrolebinding_created{clusterrolebinding="brzl-break-glass"}`,
  which the alert `BrzlBreakGlassHeld` reads.
- **Three faults found in the test, fixed in `d8a5023`.**
  - The first metric did not exist. kube-state-metrics finds
    custom-resource kinds only from CustomResourceDefinitions, and it
    skipped ClusterRoleBinding without an error. The chart's built-in
    collector replaces it.
  - Two sign-ins at once in one browser gave a 500 at the gate ("Invalid
    code_verifier"). The gate now keeps one CSRF cookie per sign-in. The
    user's test with two tabs passed. Grafana's own sign-in has the same
    fault and no setting for it: BACKLOG 34.
  - oauth2-proxy logs all cookies of a callback without its CSRF cookie.
    The log collector now redacts the values of the gate's cookies.
- **Docs.** The user did not know `as_admin` and `as_me` (Q201). They
  were only in the break-glass docs. The kiesei guide now names them, and
  it no longer tells the reader to export the cluster-admin kubeconfig.

## 2026-10-28 — pass 6b, step 2 and round 4: the reader, the person

User-verified on sleipnir, with the cluster up, at `78797ad`. Design:
Q205 to Q209, all (a) except Q205 (b) (ADR-0037, docs/BREAK-GLASS.md).
This closes pass 6b (BACKLOG item 6) and item 28.

- **The reader of the admin log store** (`reader_on`, `reader_off`,
  `driver/modes/reader.sh`). It starts a Loki and a Grafana in containers
  on the operator's machine, on `127.0.0.1:3300`, with no sign-on. Its
  Loki has the store's directory read-only and runs as a querier alone,
  so it cannot change the store. It needs no cluster and no current run,
  and it writes into its own run directory, `reader-<UTC>Z`.
- **The agent's test** (the user was away and allowed it once):
  `reader_on` printed its note about the running cluster, and Grafana
  returned the break-glass run outputs and the scale record at level
  `Request`. A second `reader_on` replaced the first reader. `reader_off`
  removed both containers.
- **The user's test** (`reader-20261028T1537Z`, `reader-20261028T1544Z`)
  gave the same results, both with rc 0. The test with the cluster
  removed (`down`) was not run.
- **Q206:** the reader runs beside a running cluster and sees records up
  to about 15 minutes late. This replaces the first design, a refusal
  while the cluster's Loki uses the directory.
- **Q207 and Q209:** on local, the cluster-admin kubeconfig and the store
  token `driver` stay. On a laptop, they give no power beyond the
  container engine's socket and the recovery key. Pass 8 decides the
  public-cloud shape (BACKLOG 23 and 29).
- **Q208:** each run output's header line names the account on the
  operator's machine, `person=<account> person_verified=false`. Both of
  the user's reader outputs show `person=rdain`. The driver's 27 test
  cases pass.

## 2026-10-28 — pass 6c: the cold log store on local

User-verified on sleipnir. Branch `pass-6c-cold-storage`.

- **The design** (Q210 to Q217). The user chose an S3-compatible store
  beside the cluster (the Versity S3 Gateway) only if the work was
  small, and said that backup and restore belong on a remote staging
  environment. The agent's estimate was the size of pass 6b. So the
  user's own rule selected files in a host directory: no S3 on local,
  and no database backups on local. The backups and a restore drill went
  to BACKLOG item 9, and the move of chofesh's AWS overlay to the Barman
  Cloud Plugin to item 10 (CNPG 1.29 deprecates the in-tree support).
- **Built.** `var/log-store/<env>/cold/` is mounted into every k3d node.
  On local, the collector's file exporter writes the records routed to
  `cold` as OTLP JSON lines, `<node>/platform/<source>.jsonl` and
  `<node>/namespaces/<namespace>.jsonl`, with every old file kept
  (`collector-local.yaml`, through `moreValueFilesLocal`). Phase 40
  checks that each admin source has a cold file that is not empty.
- **Found in the exporter's source:** without `rotation`, it empties its
  file each time the collector starts. With `rotation` set, it appends.
- **The agent's tests, without the cluster:** `otelcol-contrib validate`
  on the chart output; a throwaway collector with the same processors
  and exporter, one record, a restart, a second record, both in the file.
- **The user's live test:** `down`, `up`. Phase 40 printed the new
  check's line. The five files were under `k3d-brzl-local-server-0/platform/`.
  The `jq` command showed the API audit records of the hour.
- **The user asked for two things in RECOVERY.md:** what each cold file
  is for, and how to read them in an example incident. The agent wrote
  `driver/lib/cold-records.jq`, which prints one plain object for each
  record, and ran each example on the live records. Two faults in its
  first `jq` showed only on live data: `try fromjson catch .` returned
  the error text, not the input, and an empty event time came out as
  `{}`. Both fixed before the runbook took the examples.
- **Seen, not a fault:** the cold copy of the `down` that preceded this
  `up` starts at its fourth line. The old cluster had no cold route, so
  the first lines reached its collector and were dropped from `cold`.
  The rest waited in the queue and arrived at the new cluster. A one-time
  effect of the transition. Not verified against the admin store.
- **Argo CD after the hour.** The user reloaded Argo CD's page in a
  private window after an hour and was not asked to sign in again. The
  open item from pass 6b is closed. SECURITY.md's session table says so.

## 2026-11-04 — item 13: Argo CD v3.5, and the sync switch in place of fast mode

User-accepted ("fine for now"), with a second look planned after the next
passes. Branch `item-13-argocd-upgrade`. Designed in three rounds and one
interrupt (Q218 to Q229); built and tested by the agent on local, which
the user allowed while away (AFK, remote control).

- **Step 1, the upgrade.** Chart 7.7.23 (v2.13.4) to 10.11.6 (v3.5.6);
  the kiesei CLI 3.4.3 to 3.5.6. Annotation tracking, the v3 default
  (Q227). The chart's NetworkPolicies on (Q221): `argocd-server` open,
  repo-server and Redis only from Argo CD's own pods; core mode reaches
  them through port forwarding. Chart 10 moved Redis to
  `ecr-public.aws.com`, which no node mirrors: Redis now comes through
  Zot (imageParams and phase 30). The agent's `down` and `up`: every
  phase `.ok`, 16 Applications Synced. Record in UPGRADE.md.
- **Step 2, the sync switch** (the user's interrupt: "fast mode" no
  longer said what it does). `sync off`, `apply`, `sync on [confirm]` in
  `driver/modes/sync.sh`, on Argo CD's own `argocd app sync --local` in
  core mode. `fast-mode.sh` and its copy of Argo CD's injection are gone.
  `release` and `sync on` share one check for differences from git. The
  six kustomize Applications have one `source:`. GLOSSARY "Sync switch",
  LOCAL.md "Sync off and on", the ADR-0025 amendment.
- **The agent's live test**, after a second `down` and `up`: `apply` with
  sync on showed the diff and stopped; `sync off`; `apply` put a changed
  field in; `apply` again said "nothing differs"; with the tree reverted,
  `sync on` refused with the exact diff; `sync on confirm` healed at once.
- **Three findings on the way, each fixed and documented:**
  1. Argo CD's local render runs `kustomize edit` in place. The first test
     rewrote two kustomizations (the portal's here, chofesh's
     `deploy/local`), both restored with git. `apply` renders a copy.
  2. After a local sync, Argo CD compares against what it last synced,
     not git, and a hard refresh does not change that. The first check
     passed a real drift. `sync on` now diffs against the git revision
     and syncs each kustomize Application from git before the switch.
     This was the safety the user asked for (Q225), so it took three runs.
  3. A field that only the working tree added is no difference for Argo
     CD, and it stays after `sync on`. LOCAL.md says so.
- **The agent's own faults, seen in the tests:** an exit code read from
  a `grep` in a pipeline (inverted), no check after each sync, and one
  claim that the spike had passed when its edit had not matched the file.
- **On the user's request (2026-11-04):** the new run sheets have one
  command per line. Checked with `bash -n` on the emitted streams; Docker
  was not running then, so not on a live cluster. The rule for all
  emitters is BACKLOG 36; `hold`/`release` naming is BACKLOG 35.
- **Left behind:** the annotation `brzl.dev/spike=item-13b` on the
  binding `brzl-tier-auditors`, from the test. Harmless; the next `down`
  and `up` removes it.

## 2026-11-05 — item 37: the driver grammar

**User-verified 2026-11-05.** The user ran the full loop on the live
local cluster: `cluster bootstrap`, `break-glass open`, `apply` with a
change, `close`, `close confirm`, and the guard on `audit teardown`.
Branch `item-37-driver-grammar`, merged to `main` with `--no-ff`.
ADR-0038.

- **The origin.** Item 35 renamed `hold`/`release` to `pause`/`resume`
  (built 2026-11-04). The user tried it and saw two things. The sync verbs
  and the break-glass pair move one switch. And the driver mixed nouns
  and verbs. Item 35 was dropped (Q234 b: "failure and cutting changes
  also counts as progress"), and item 37 took its place.
- **The grammar** (the user, Q235–Q240): `BRZL_ENV=<env> driver.sh <mode>
  <verb>`. The mode `cluster` has `bootstrap`, `teardown`, `status` and
  `check`. `next` is gone, because `bootstrap` resumes. The mode
  `break-glass` has `open '<reason>'`, `apply [<dir>]` and `close
  [confirm]`. `sync off` and `sync on` are gone, and `apply` refuses
  unless the break-glass is open. The mode `audit` has `bootstrap` and
  `teardown`, for the reader. `start` and `stop` are synonyms. `BRZL_ENV`
  defaults to `local` until BACKLOG 38 (Q242). `open` without sign-on
  names the host account as declared (Q241). The names follow (Q243):
  `modes/audit.sh`, no `modes/sync.sh`, `break-glass-open-` and
  `-close-`, `audit-<UTC>Z`, `BrzlBreakGlassOpen`, `brzl-audit-<env>-*`.
- **The teardown guard** (the user, Q238, and Q244). Every line is behind
  `## ⚠ ##`. The first line sets `guard=stripped`. The last group tests it
  and, without the `sed` in the pipe, prints the footer to stderr and
  exits 2. The first shape, a footer on stdout, showed nothing when
  nothing ran. The second, a one-line test, was messy in the preview. The
  third is five lines with a heredoc. The user removed the space after
  the prefix.
- **Found in the live test, fixed.** An edit to the example app's
  `namespace.yaml` showed no diff. The cause is kustomize, not the
  driver: the base kustomization's `namespace:` renames `Namespace`
  objects too. The kiesei shell's login and `open`/`close` ran `kubectl
  auth whoami` with stderr thrown away, so kubelogin's URL never showed.
  The shell looked hung, and `open` waited 30 s. Both now show the output
  and say what happens.
- **The user's GLOSSARY edits**, with the documents that follow. The
  kiesei runs at one of two loci, not "in two modes". "TLS mode" is "TLS
  type".
- **Method.** Three rounds, Q234–Q244. Two forks wrote BREAK-GLASS.md and
  LOCAL/INSTALL/kiesei.md in parallel, and their diffs were read. One
  commit went in before its lint result was read, and the next commit
  repaired it. 39 driver tests. The item-35 branch is the user's to
  delete.
