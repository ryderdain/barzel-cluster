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

