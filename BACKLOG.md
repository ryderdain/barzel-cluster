# BACKLOG — planned work (shared)

The explicit plan-of-record, edited by **both** the user and the agent. Items
land here when decided, move to [SCRATCHPAD.md](SCRATCHPAD.md) while being
worked, and produce a [RETROSPECTIVE.md](RETROSPECTIVE.md) entry when done and
user-verified.

## Active — the platform, local first

barzel-cluster is a **platform**: a general, secured Kubernetes cluster that
runs on several substrates (k3d, AWS, GCP, DigitalOcean, …) with as few
changes as possible, as the backbone of a CI/CD chain. It does not depend on
any workload (user, 2026-10-14). Vocabulary: [GLOSSARY.md](GLOSSARY.md).
Decisions: [SPEC.md](SPEC.md) §3 and [docs/adr/](docs/adr/). One line per item;
the detail lives in the linked ADR. Q-numbers refer to the design rounds.

Done (verified live; see [RETROSPECTIVE.md](RETROSPECTIVE.md)):

- Passes 0–1: ADR migration; the Bash doctrine in `ryderdain/bash`.
- Pass 2: driver + k3d adapter (2026-10-09; ADR-0021, ADR-0022, ADR-0024).
- Pass 3: Zot beside the cluster, kiesei, warm conductor (2026-10-09; ADR-0023).
- Pass 4: Argo CD, one platform ApplicationSet, fast mode (2026-10-13; ADR-0025).
- Pass 5: ESO 2.12, OpenBao outside the cluster (2026-10-13; ADR-0026).

Order of work (Q120):

1. **Cleanup round** — done 2026-10-14.
2. **5c. Admin portal** (now, branch `pass-5c-portal`) — nginx serves a
   static page and passes each path to its service; TLS `letsencrypt` or
   `local-ca` ([ADR-0028](docs/adr/0028-admin-portal.md)). Q126: a `portal`
   element in the platform ApplicationSet. Q127: host port 443 to a node
   port; Traefik and the service load balancer of k3s turned off.
   Q128–Q137 ([ADR-0036](docs/adr/0036-cert-manager-and-local-stand-ins-for-public-services.md)):
   cert-manager renews; the issuer is the environment's TLS mode;
   `local-ca` on local, `letsencrypt` in pass 8; a CoreDNS stand-in for
   public DNS; `BRZL_PORTAL_HOST` is a value (`local.barzel.sh`).
3. **5d. Example app** — **done 2026-10-18** (RETROSPECTIVE; four live
   tests, user-verified). `chofesh` (now `tzvat/chofesh`) gained `chofesh serve`, a Dockerfile and
   `deploy/{base,local,aws}`. The demo-app and postgres bases and overlays
   and `apps/demo-app` left this repo
   ([ADR-0034](docs/adr/0034-example-app-is-a-separate-workload.md)).
   Decisions: Q141 (b), phase 20 builds the image from the checkout beside
   the repo until pass 8. Q142/Q146, the manifests live in chofesh, Argo CD
   reads them from the public repo at `main`, fast mode from the checkout.
   Q143/Q147, the credential stays CNPG's, in the app's namespace. Q144,
   relative links and no base-path flag. Q145, git in chofesh is delegated
   like this repo. Then (2026-10-18) Q148–Q152 replaced the driver's build:
   the app's CI publishes the image, releases are tags made with
   `make release`, and the environment's follow policy (`branch` on local,
   through an SCM generator; `release` elsewhere) picks the commit and the
   image. chofesh moved to the `tzvat` organization for the generator.
   Then Q153–Q157: the workload is private (repo and package). A GitHub
   App and a `read:packages` token, made by `driver/access/github.sh` into
   `var/access/github/<org>/`, are seeded into the store by phase 25. One
   `repo-creds` Secret per organization. `docs/INSTALL.md` is the front
   door for a new user.
4. **6. Logs** — collector, admin and diagnostic Loki, Grafana; UTC
   everywhere; run directories `cluster-<UTC>Z` / `teardown-<UTC>Z`; a header
   line in each run output; API and OpenBao audit logs
   ([ADR-0027](docs/adr/0027-logs-admin-and-diagnostic-stores.md)).
   Design round 2026-10-19 (Q158–Q162, the ADR's amendment). Metrics go
   to every substrate, and kube-prometheus-stack's Grafana is the one
   viewer. Loki and the collector come from Helm charts. The local
   collector beside the cluster sends to the one in it, with a queue on
   disk. **DONE 2026-10-21, user-verified** (RETROSPECTIVE).
4a. **HIGH PRIORITY: a credential on the collector's OTLP receiver**
   (user, 2026-10-21). The in-cluster collector accepts OTLP on its host
   ports 4317 and 4318 without a credential. Any pod, and any container on
   the local network, can write records that the platform routes into the
   admin log store, as if they were run outputs or audit records. This
   breaks the admin path's purpose, the audit trail. Do it before 6a or as
   its first step, and before any shared environment. Candidates: a bearer
   token from the cluster secret store, checked by the receiver
   (`bearertokenauth`), or mTLS with a certificate from the local CA.
   Either way, only the collector beside the cluster holds the credential.
   [ADR-0027](docs/adr/0027-logs-admin-and-diagnostic-stores.md), "Open
   after pass 6". Decided 2026-10-22 (Q163–Q166): mutual TLS from the
   store's CA. **DONE 2026-10-22, user-verified** (RETROSPECTIVE).
5. **6a. SSO, local and remote** — Dex + oauth2-proxy in front of nginx; it
   leads to the admin portal, which also works without it (Q108, Q112).
   Scope (user, 2026-10-16, Q144): SSO covers the admin landing page and
   the admin services. A workload is not behind it unless it has a
   management UI of its own (chofesh has none). The legacy local SSO path
   (`gitops/clusters/local/{k3d-up.sh,sso/,kustomization.yaml}`) still
   names the demo-app and is stale since pass 5d. This pass replaces it.
   Designed 2026-10-23 (Q169–Q183, ADR-0035 and ADR-0028 amendments).
   **Step 1, web sign-on: done and user-verified 2026-10-23**
   (RETROSPECTIVE). The legacy path is removed. Step 2: `kubectl` through
   Dex (Q174), designed 2026-10-26 after a review of every auth flow
   (`notes/AUTH-FLOWS.md`, local). When the decisions of this pass are
   made, bring the relevant parts of that review into SECURITY.md and
   SECRETS.md. Also add to SECRETS.md one table per root of trust, which
   lists what derives from it (user, 2026-10-26). The roots are the
   store's files, the cluster-admin kubeconfig and the operator's `gh`
   login.
6. **6b. Break-glass mode** — `hold` / `release`; the procedure through the
   conductor; a record of each use; a Grafana reader of the admin store that
   runs only in break-glass mode and also loads the newest cold records
   (Q62–Q65, Q94, Q107).
7. **6c. Cold storage + backups** — the `cold` route; each workload's
   database backups (Q92).
8. **7. `promote platform`** — roll a platform revision one environment at a
   time (Q118).
9. **7h. Remote harness** — a second host (huginn, VMs on sleipnir, or
   OpenStack) to model a shared remote environment (Q116, deferred).
10. **8. Substrate adapters** — one pass for each: first the shared interface
    and AWS, then others. Open items for AWS: the secret-store adapter
    (Secrets Manager) and `gitops/clusters/{dev,prod}/secret-store/`; the
    ECR pull-through for `ghcr.io` needs an upstream credential (a GitHub
    token in Secrets Manager) before dev can pull the example app's image;
    the AWS runbooks and the legacy AWS scripts (`platform.sh`,
    `bootstrap-argocd.sh`, `seed-demo-data.sh`, the Terraform ingress) still
    name the demo-app and `gitops/operators/postgres`, where only the DR
    recovery artifacts remain; the
    `letsencrypt` TLS mode (an ACME `ClusterIssuer` with DNS-01 at FreeDNS
    in `gitops/clusters/<env>/pki/`; whether a cloud needs the store copy of
    the certificate; ADR-0036); the
    admin log store (Q96: same product, data in S3); shipping the driver's
    run sheets (Q106); from pass 6 (ADR-0027 "Open after pass 6"): the k3s
    audit policy and log file through Ansible, the portal host annotation
    for Grafana's domain, the Grafana password from the AWS store (the
    bootstrap's `grafana-admin` goes), the events from one collector
    replica; the OTLP receiver's certificates on a cloud: a private or a
    public CA (the user, 2026-10-22), a token only if it brings a clear
    gain; exposing nginx through the Gateway API (Q113); the
    CloudWatch Logs exporter is alpha; the live test of model B
    (`terraform/stack/aws`, never applied); an automated full-teardown sweep;
    `ebs-csi/values.yaml` pins `brzl-dev-k8s` for prod too; the conductor and
    multi-account direction (SPEC §9). Driver credentials (user,
    2026-10-14): `driver/kiesei.sh` mounts only the engine socket and the
    repo and passes `BRZL_*`; no `~/.aws`, no `AWS_PROFILE`. Either mount
    `~/.aws` read-only and pass `AWS_PROFILE` (AWS SSO keeps its session
    cache in `~/.aws/sso/cache`), or export short-lived credentials into
    the container (`aws configure export-credentials`). A wrong-account
    guard: a phase-10 check compares the caller's identity with a marker
    the environment expects (an account alias or a tag, not a committed
    account ID, which would break the derive-at-runtime rule). SSO login:
    an expired session stops the phase with a fix line (`aws sso login
    --profile …`) instead of a credential error in the middle of a run.
11. **9. `promote workloads`** and **`promote all`** (a platform and workload
    change that depend on each other) (Q118). Revisit the Flow diagram in
    ARCHITECTURE §1 then, for the workload repo's branches (user). The
    example app's `deploy/aws` overlay (backups, metrics, dashboard) was
    carried over verbatim in pass 5d and is untested until this pass.
12. **Documentation run: the guidebook** (after the last passes; user,
    2026-10-15). One file for each tool or component in `docs/guide/`, for a
    reader who is new to it: the basics, how it works, how this repo uses
    it, with diagrams like those in ARCHITECTURE. For example: Kustomize,
    Helm, OpenTofu, Ansible, Argo CD, OpenBao, ESO, CNPG, Zot, k3d/k3s,
    nginx, the log stack (OpenTelemetry Collector, Loki, Grafana), and each
    operator or controller that the platform adds. **Write a draft when a
    pass first uses a tool or decides to add it**; the run completes them.
    Drafts so far: [Kustomize](docs/guide/kustomize.md),
    [cert-manager](docs/guide/cert-manager.md),
    [kiesei](docs/guide/kiesei.md), [the log stack](docs/guide/logs.md).
13. **Argo CD upgrade** (user, 2026-10-15): chart 7.7.23 (v2.13.4; the
    patch that fixed the login `return_url` under a base href, taken in
    pass 5c) to the current chart (10.x, v3.5). Aligns the server with the
    `argocd` CLI in kiesei (3.4.3).
14. **The `*.localhost` default test** — done 2026-10-15 (RETROSPECTIVE);
    sleipnir is back on `local.barzel.sh`, the reference chosen-name case.
15. **The ApplicationSet itself is not in GitOps** (found 2026-10-15): phase
    30 applies `gitops/platform/applicationset.yaml`; a change to it (a
    chart version, a new element) reaches the cluster only when phase 30
    runs again, while the values files and manifests it points at follow
    git. Options: Argo CD manages the ApplicationSet from git (an
    Application for `gitops/platform/`), or the driver says so plainly.
    Decide with pass 7 (`promote platform`), which is about moving the
    platform revision.

    **Incident, pass 5d live test (2026-10-16/18), to read again here.**
    The pass removed the `postgres` and `demo-app` elements. The procedure
    I gave was "delete the two Applications, then `up`". It failed twice,
    for two reasons that both belong to this item.

    *The orphan guard.* Phase 30's run sheet has four groups: install Argo
    CD, register the cluster (AppProject, cluster Secret), the guard, apply
    the ApplicationSet. The guard reads the element names from the file at
    emit time and the live Application names on the conductor at run time.
    When a live Application has no element, it stops the sheet with
    `error 3` before the apply group (ADR-0016, ADR-0025). The
    ApplicationSet never deletes an Application (`create-update`), so an
    orphan is the operator's decision. The guard worked as designed.

    *Attempt 1.* The live ApplicationSet still had the two elements, so it
    recreated the Applications one minute after the delete. Phase 30 wrote
    the cluster Secret (revision `pass-5d`), then stopped at the guard. The
    two old Applications now pointed at a branch without their paths
    (ComparisonError), and the portal's new pod crash-looped until the
    `chofesh` Service existed. The conductor also scaled itself to zero in
    the middle of phase 40. Its idle timer counted only run-sheet starts,
    and phase 40's two 900 s waits exceed 1800 s. Fixed:
    `driver/conductor/conductor.yaml` counts a running sheet as activity.

    *Attempt 2.* The check of phase 30 wrote `30-gitops.ok` on attempt 1.
    It only asked whether Argo CD was up and whether the ApplicationSet,
    the old one, was `ResourcesUpToDate`. `up` skips a
    phase with an `.ok`, so it ran phase 40 alone against the old
    ApplicationSet: no `chofesh`, the portal never Healthy, the wait "hung
    on pki" (the last Application printed before `portal`). Fixed: the
    check now compares the live element names with the file's and fails
    with both lists when they differ (commit `a3b2f42`). I removed the two
    stale `.ok` files by hand.

    *The procedure that works* (now in LOCAL.md "Retire an Application" and
    ADR-0025): drop the element from the live ApplicationSet with a JSON
    patch, delete the Application, delete its namespace, then `up`. It is
    manual because phase 30 applies the ApplicationSet, and Argo CD does
    not follow it from git. When this item is decided, the procedure should
    become one driver action or go away: with the ApplicationSet in
    GitOps, Argo CD would show the orphan and the operator would prune it.
16a. **The workload's access setup is clunky** (user, 2026-10-18, after the
    first onboarding with `driver/access/github.sh`): six steps, three of
    them in the browser, and it is no longer clear which commands run on
    the host and which in kiesei. Revisit in a later pass: run the
    management through kiesei as a rule, with a way to hand the browser
    steps (and the clipboard) to the host; fewer steps where GitHub's API
    allows; the same shape for other hosts (GitLab, ...). Also the
    platform's own deploy key (the standing concern below) through the
    same App.
16b. **Small annoyances for the operator in kiesei** (user, 2026-10-18):
    logging in to Argo CD from the kiesei shell takes four lines (export
    the kubeconfig, read the admin password from its Secret, `argocd login`
    with the host, the root path and the user). The fewer such details an
    operator must keep, the fewer any user must. Candidates: the shell
    starts with KUBECONFIG set and the Argo CD context logged in (pass 6a's
    SSO changes the login anyway); one `brzl` helper for the common
    lookups; the portal page lists exactly what is left. Tested fast way
    for `argocd` (2026-10-18): core mode needs no server, no password and
    no login, only the kubeconfig with the namespace `argocd` as its
    context's namespace. So kiesei.sh can export `KUBECONFIG` to the current
    run's kubeconfig and `ARGOCD_OPTS="--core --kubeconfig <a copy with
    namespace argocd>"`, made at start; then
    `echo argocd app list | bash driver/kiesei.sh` works as is. Core mode
    bypasses Argo CD's own RBAC: right for the operator with the
    cluster-admin kubeconfig, not for a user with limited rights.
16c. **Manifests as files in the run directory** (user, 2026-10-18, from
    reading the fast-mode run sheet). Today the emitted groups wrap each
    rendered manifest in a `kubectl apply -f - <<EOF` heredoc. Clearer: the
    group writes the manifests as YAML files in `var/run/<env>/<run>/`, one
    object or one app per file. Then it applies them by file name, or
    `tee`s them in. Then an operator can read a manifest later on its own. The
    core style idea: the stream emits each manifest alone, so that a
    redirect puts it in a file. That is one more pipe segment in the
    driver's emitted actions. It is either a doctrine update in
    `ryderdain/bash` (STYLE §1.2, emitted groups) or a mistake here to
    correct against the doctrine. Decide with the doctrine's owner, then
    apply it to fast-mode.sh and the phases.
16. **Parked: `driver.sh <env> again <phase>`** — run one phase again on a
    finished cluster, with the conductor install in a phase of its own
    (Q130 b). **Only in case a later pass needs it**; certificate renewal
    does not (cert-manager, ADR-0036).
17. **`driver.sh <env> state`: list the state kept outside the cluster**
    (proposed 2026-10-14 in the review of the design's shape, then Q161,
    2026-10-19). That state keeps growing, as Q66 intends. It holds the Zot
    cache, the OpenBao volume with its seal key and tokens, the local CA,
    the access files and the run directories. From pass 6 it also holds the
    admin log data, the collector's queue and later the cold copy. Nothing
    lists all of it in one place. The command is a read-only generator: each item with its
    location, size and age, and the CA trust in the keychain as a reminder.
    The removal of each item stays a documented command in LOCAL.md.
18. **A purge for rapid teardown and cleanup** (user, Q161, 2026-10-19).
    Separate from `state`. It returns the machine to a clean start in one
    step, for rapid prototyping of different modes. It needs safeguards.
    It is an emit script whose preview names every item. It stops with
    `error 3` while a cluster is up. It states what it keeps, for example
    the access files, which take browser steps to make again.
19. **A low-memory mode** (user, Q158, 2026-10-19). The full local
    environment used 5.0 GiB with metrics and logs (pass 6, measured). huginn
    (8 GB) and other small machines cannot run it. A mode that turns off
    or shrinks the heavy parts with few design changes, built only when a
    need for it appears.

20. **Argo CD gives up after five failed syncs** (found 2026-10-22, live
    test of 4a). For about 1 h 40 min, lookups of public names from the
    pods failed in bursts (CoreDNS forwards to Docker Desktop's resolver),
    while the node resolved them. `monitoring` used its five retries
    (`retry.limit: 5`, at most 3 minutes apart) and stopped. After that,
    Argo CD does not retry an automated sync of the same commit. So phase
    40 waited until an operator refreshed and synced by hand. Options: no
    limit (`limit: -1`, a negative limit means no limit), a larger limit,
    or a refresh and sync step in phase 40 before its wait. **Decided and
    built 2026-10-22 (Q167, Q168).** There is no limit now. Phase 40
    names an Application that fails 3 times or more. The Prometheus alert
    `BrzlSyncFailing` fires at 3 (warning) and 5 (critical), shown in
    Grafana. **DONE 2026-10-22, user-verified** (RETROSPECTIVE).
21. **A channel for alerts** (user, Q168, 2026-10-22). No Alertmanager
    runs, so an alert such as `BrzlSyncFailing` only shows in Grafana and
    Prometheus. Choose a channel (e-mail, Slack, ntfy, or Argo CD's own
    notifications) and its credential, then turn on Alertmanager with that
    receiver.
22. **The GitHub dependency, examined alone** (user, 2026-10-23, during
    the 6a design). Find each place where the platform needs GitHub. Argo
    CD reads this repo and the workload's repo from it. The workload's
    image comes from its registry. The App and the packages token are
    GitHub credentials. Sign-on (6a) uses GitHub as the identity provider.
    Then find if a general case exists for the git host, so that GitLab,
    Bitbucket or a self-managed git server can take its place.
    State what each part would need, and what is specific to GitHub. Each
    other provider needs its own access script beside
    `driver/access/github.sh`, with the same output layout: the read
    credentials, the sign-on client and the teams or groups (user, Q183).
    The access setup stays separate from the platform's own authentication
    and authorization.
23. **The cluster-admin kubeconfig after bootstrap, on a public cloud**
    (user, Q174, 2026-10-23). Phase 10 writes a kubeconfig with
    `cluster-admin` to `var/run/<env>/`, and the driver keeps it. It is a
    standing credential that skips sign-on. Locally it is the emergency
    path (Q175). On a public-cloud substrate, it must not stay after
    bootstrap without a decision. Add a validation check that fails when a
    public-cloud environment still has such a kubeconfig after bootstrap.
    Then decide the emergency path there, for example a short-lived
    credential from the cloud's identity service. Do it in pass 8, before
    the first public-cloud environment.
24. **A workload viewer tier** (user, Q170, Q173, Q179, 2026-10-23). A
    restricted access tier for the people who develop one workload: in
    Grafana, only that workload's logs (the diagnostic log store, its
    namespace). The sign-on gate must be able to admit this tier, and only
    to Grafana. Check first how to limit a data source in Grafana's free
    edition (a separate Grafana organization, possibly). Build it when a
    workload developer who is not an operator exists.
25. **Review: a read-only check in a script of emitted steps** (user, Q184,
    2026-10-23, for the user, against the doctrine in `ryderdain/bash`).
    `driver/access/github.sh` emits every step except `check` and
    `sign_on_check`, which run directly, as bash-ops §1 says a read-only
    check must. The user found that this reads as inconsistent. Decide if
    the doctrine changes (for example, a check in an emit script also
    emits), or if the script makes the difference plainer (one `check`, or
    a usage line for each step). Until then, the script stays as it is.
26. **Sign-out** (user, Q185, 2026-10-23, to revisit later). Grafana's and
    the portal's "Sign out" sign the person in again at once: Grafana
    signs in automatically, Dex keeps no session, and GitHub keeps its
    own. The proposal: one sign-out for the portal, Grafana and Argo CD
    (Grafana's `signout_redirect_url`, Argo CD's `logoutURL`), ending on a
    static page outside the gate that says GitHub keeps its session.
27. **oauth2-proxy trusts `X-Forwarded-*` from any address** (found
    2026-10-23, pass 6a). With `reverse_proxy` on and no
    `trusted_proxy_ip`, any pod that reaches oauth2-proxy directly can set
    those headers. Limit them to the portal (its pod network, or a
    NetworkPolicy that admits only the portal).
28. **An emergency Grafana for the backed-up logs** (user, 2026-10-26).
    Since sign-on, Grafana has no emergency path: its login form and
    basic auth are off, so `grafana-admin` opens nothing (found in the
    auth-flows review, `notes/AUTH-FLOWS.md`). When the cluster is down
    or out of reach, the operator needs the admin log store. Prepare a
    thin image that runs Grafana alone, outside the cluster, as a UI for
    the backed-up logs (local: `var/log-store/<env>/admin/`).
29. **The driver is a machine identity in every scenario** (found
    2026-10-26, `notes/AUTH-FLOWS.md`). Every phase acts as
    `system:admin` (the kubeconfig) and as the store token `driver`. The
    API audit log and the store's audit log cannot name the person who
    ran a phase. Only the shell on the operator's machine knows. Step 2 of
    pass 6a (`kubectl` through Dex) names a person for `kubectl`, not for
    the phases. Decide with item 23 whether the driver should act with a
    person's identity on a public cloud.

Standing concerns (check in every pass):

- **GitHub App before leaving local** (Q61). The repo is private. Argo CD on
  local reads it with the read-only deploy key `sleipnir-brzl-deploy`
  (bootstrap source `BRZL_REPO_DEPLOY_KEY`). Replace it with a GitHub App
  credential before pass 7h or 8. The workload side is done in pass 5d
  (`driver/access/github.sh`, a GitHub App per organization, Q154 b). The
  same App on the platform's organization can replace the deploy key.
- **Every phase must be safe to run again** (`ryderdain/bash` STYLE §1.11,
  ADR-0022). Review each new phase script for converging commands.
- **Platform-layer portability** (SPEC §3). The platform layer assumes only
  conformant Kubernetes and the adapter's outputs. The legacy SSO edge
  (`gitops/clusters/local/sso/`, Traefik `IngressRoute`) violates it; pass 5c
  replaces its routing, pass 6a its sign-on.
- **ESO in-place upgrades** go one minor at a time and check
  `status.storedVersions` on the four ESO CRDs. Write into `docs/UPGRADE.md`
  in pass 8.
- **Resource budget**: sleipnir 32 GB, huginn 8 GB ([docs/LOCAL.md](docs/LOCAL.md)).
- **`notes/` history scrub** — decision pending with the user (it rewrites
  published history).
- **Port the seed's §1.10** ("a script's claims are part of its contract") to
  `ryderdain/bash` STYLE.md.
- **Operator steps stand out** (user, 2026-10-15): a step the operator must
  do by hand prints in a boxed block on stderr (`operator_step`,
  `driver/lib/phase-common.sh`), for the driver machine's OS
  (`BRZL_HOST_OS`, set by `driver/kiesei.sh`). Port the convention to
  `ryderdain/bash` STYLE.md with §1.10.
- **Before going public on GitHub** (user, 2026-10-14): redraw the ASCII
  diagrams in ARCHITECTURE and README as Mermaid; a cosmetics pass on the
  docs. Last thing, not now.
- **Markdown lint debt**: about 600 older errors (mostly MD013) in SPEC,
  SCRATCHPAD and the runbooks. Clean a file when a pass edits it. Do not
  change RETROSPECTIVE entries without asking.

## Earlier plans (before the local-first refactor; kept as written, review later)

## Active — the major refactor (next barzel session) + aroni assists

**The refactor is the next focus** (items 1–4 below: automation overhaul vs
`notes/GUIDANCE.md`; env DRY/consolidation; multi-account CI). **aroni should drive
it forward** — and the refactor will *generate aroni's next corpus*: every decision,
failure, and fix is an episode. Log them (RETROSPECTIVE / a build ledger) as you go;
consolidate periodically. Watch for the first **co-firing** between existing notes —
that's the event that admits cand-005 and exercises the closed loop for real.

## aroni (consolidation daemon) — machinery complete through 2nd order

Self-contained shared vault at `~/Local/github.com/ryderdain/aroni` (b5744e3): 4
admitted notes, 17 episodes, doctrine (subordination, seam test, intersection test,
co-fire loop — all in METHOD), survival hooks, portable (`init_project`). The
co-fire re-evaluation loop is **closed + enforced** (vault_check + intersections
--work-order). cand-005 (first 2nd-order note) is HELD pending a real co-firing.
Open threads:

- **Next cycle:** ingest the 3 new surprise-0 RETROSPECTIVE episodes; normal pass.
  Also drain the two new **inbox** captures (2026-06-15): the brzl-dev-* standalone-path
  leak (cand-002 evidence) + the instances-vs-source-layout correction (cand-005 framing).
- **Hooks gap (→ aroni BACKLOG, 2026-06-15):** no hook auto-captured the in-session
  correction this session; it took a manual "aronize it". Capture still leans on operator
  memory — the dependency the method exists to remove. Tracked in aroni BACKLOG ("No
  auto-capture of in-session episodes"); sibling of the surprise-mis-tag gap.
- **Fully automating the co-fire re-gate** (vs the current detect+enforce, judge-by-hand)
  — only if it ever proves a bottleneck; the judgment is deliberately human.

- **aroni `lift` is not calibrated across models/sessions** (ordinal, judge-relative).
  A future "re-gate with one judge" pass before any cross-pass score comparison.
  Tabled 2026-06-14. (At second order, lift is already demoted to a sanity check.)
- Seeds: fix-propagation bundle (h3 + a sibling, needs a 2nd episode); cand-005 admits
  on its first demonstrated co-firing; cand-001/003 refinement (arbiter-flagged).

## Planned (user, 2026-06-10 — in intended order)

1. **Automation-methodology overhaul.** Bring all tooling — `platform.sh`
   itself included — into closer adherence with `notes/GUIDANCE.md`. Expect
   multiple passes; this will not complete in one.
2. **Polish `notes/GUIDANCE.md` itself** — as much for the user as for the
   agent.
3. **Environment realignment.** Simplify and consolidate the operational
   paths: bootstrapping on local, dev, and prod.
   **Reframed (user, 2026-06-14):** the goal is NOT to collapse dev and prod into
   one definition — the parallel same-root-structure trees are *the point* of a
   dev→staging→prod split: you prove the pre-production model + code in dev before
   applying it to the reputation-exposed prod. Over-DRYing them away destroys that
   promotion gate. So the real target is the distinction:
   - **Intentional separation — KEEP:** each env is its own independently-promotable
     instance (own state/tfvars, own ApplicationSet apply), so a change lands in dev,
     is validated, then promoted to prod. Real per-env differences (prod private
     nodes + NLB/NodePort, instance sizes, conductor is dev-only) stay explicit.
   - **Accidental coupling/drift — FIX:** shared code that hardcodes one env (the
     `brzl-dev-*` leaks into env-agnostic scripts), and hand-maintained near-duplicate
     files that silently DRIFT (the 2026-06-10 ApplicationSet divergence *bug*). DRY
     belongs in shared **modules/templates** (define once, instantiate per-env), not
     in merging the instances. The divergence bug argues for reducing the
     hand-maintained surface, NOT for one-file-for-both.
   **Direction chosen (user, 2026-06-15): model B** — single source per layer + per-env
   `backend.hcl` + `terraform.tfvars`, driver-enforced backend↔tfvars pairing. Keeps
   separate state + independent apply (the gate); kills drift; fits the per-env-backend
   convention + the item-4 multi-account roadmap. Workspaces (C) rejected (weak state
   isolation, fights multi-account, switch footgun). Per-env structural deltas stay
   explicit: prod-only NLB → `count`/`var.enable_public_ingress`; node placement → vars;
   `00-conductor` stays its own optional standalone layer. **Merge plan pending user review
   before execution** (prototype on `10-network` first, prove the pattern, then roll).
   Full live validation deferred to the batch live-pass; in pass-1 (item 3) the standalone
   DR path was already de-pinned (commit 6941c78).
4. **Multi-account CI design.** Expand the brzl demo model to showcase
   local-dev → infra-test → full-with-app-staging → full-prod across accounts
   — the piece the take-home never reached; have it ready to deliver for a
   similar interview.

## Carried over from the take-home (post-delivery candidates)

Most fold naturally into the numbered items above; tracked here until they do.

- Root-app pattern for the ApplicationSet (close the GitOps seam — ADR-0019
  names the design: include-glob `applicationset.yaml` + `project.yaml`,
  exclude `in-cluster.yaml`). → item 3
- ~~`platform.sh` `operator()` phase: comment claims it installs EBS CSI + gp3,
  body doesn't (open since the A2 drill).~~ → item 1 — **DONE (pass 1, pending live
  verify):** `operator()` now installs EBS CSI + gp3 via the new
  `gitops/bootstrap/install-ebs-csi.sh` (emit-style, renders the SAME committed
  ebs-csi values the ApplicationSet wave 0 uses → can't drift), then asserts the
  gp3 class exists before continuing. RECOVERY.md Step 4 updated.
- ~~Driver hardening: preflight per-layer `backend "s3"` blocks; print "next
  phase: X" on any phase failure.~~ → item 1 — **DONE (pass 1, pending live verify):**
  `preflight()` now asserts every layer declares `backend "s3"` (missing = silent
  LOCAL state); `_run_phases` prints the stopped phase + exact resume command (+
  phases not reached) on any failure, dual-mode (EXIT trap for direct runs,
  return-catch when sourced — no parent-shell trap pollution).
- **Pass-1 also:** renamed `generate-inventory.sh` → `generate-inventory.sh`
  (snake_case rule; all live callers updated, `notes/` history left as-is).
- **Discovered (→ item 3, env-DRY / aroni cand-002 env-coupling):** the shared
  `gitops/infrastructure/ebs-csi/values.yaml` hardcodes the `brzl-dev-k8s`
  pull-through prefix; both dev AND prod ApplicationSets (and now the standalone
  DR install) consume it, so prod's CSI sidecars pull through a `brzl-dev-*`
  repo. The whole recovery path is similarly dev-pinned (`cluster-recovery.yaml`
  → `brzl-dev-github`). Left faithful for now (changing it would diverge the
  standalone path from GitOps); fix env-wide in item 3.
- Generalize local-first state + `init -migrate-state` promotion as the
  bootstrap-from-zero mechanism (and its reverse for retirement) — noted in
  `docs/TEARDOWN.md` §3 / `docs/BOOTSTRAP.md` Phase 0. → items 1, 3
- Conductor repo-read credential (fine-grained PAT, Contents+Metadata) to
  replace the S3 tree-ship one-off. → item 1
- Register this repo's deploy key (public half) before the first GitOps
  bring-up here.
- ECR/Harbor image vulnerability scanning gate (scan-on-push, fail-on-critical).
- Re-enable Alertmanager with a real receiver (one-line flip, needs a target).
