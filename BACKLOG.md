# BACKLOG — planned work (shared)

The explicit plan-of-record, edited by **both** the user and the agent. Items
land here when decided, move to [SCRATCHPAD.md](SCRATCHPAD.md) while being
worked, and produce a [RETROSPECTIVE.md](RETROSPECTIVE.md) entry when done and
user-verified.

## Active — the platform, local first

barzel-cluster is a **platform**: a general, secured Kubernetes cluster that
runs on several substrates (`local` with k3d, `aws`, `gcp`, DigitalOcean,
…) with as few changes as possible, as the backbone of a CI/CD chain. It does not depend on
any workload (user, 2026-10-14). Vocabulary: [GLOSSARY.md](GLOSSARY.md).
Decisions: [SPEC.md](SPEC.md) §3 and [docs/adr/](docs/adr/). One line per item;
the detail lives in the linked ADR. Q-numbers refer to the design rounds.

Done (verified live; see [RETROSPECTIVE.md](RETROSPECTIVE.md)):

- Passes 0–1: ADR migration; the Bash doctrine in `ryderdain/bash`.
- Pass 2: driver + k3d adapter (2026-10-09; ADR-0021, ADR-0022, ADR-0024).
- Pass 3: Zot beside the cluster, kiesei, warm conductor (2026-10-09; ADR-0023).
- Pass 4: Argo CD, one platform ApplicationSet, fast mode (2026-10-13; ADR-0025).
- Pass 5: ESO 2.12, OpenBao outside the cluster (2026-10-13; ADR-0026).
- Passes 5c, 5d: the admin portal, the example app (2026-10-18; ADR-0028,
  ADR-0034, ADR-0036).
- Pass 6, 6a, 6b, 6c: logs, sign-on, break-glass, cold storage
  (2026-10-28; ADR-0027, ADR-0035, ADR-0037).
- Items 13, 37, 38, 39: the Argo CD upgrade, the driver grammar, the
  environment names, the kiesei stages (2026-11-05; ADR-0038, ADR-0039,
  ADR-0040).
- Item 36: one command per line in the emitted streams (2026-11-06, the
  rule in `ryderdain/bash` STYLE §1.2).

Each done item below keeps its number and one short entry, because other
documents and notes name items by number. The record is RETROSPECTIVE.

Order of work (Q120):

1. **Cleanup round** — done 2026-10-14.
2. **5c. Admin portal** — **done 2026-10-15** (RETROSPECTIVE; ADR-0028,
   ADR-0036): nginx and the portal page, cert-manager, the TLS type
   `local-ca`, the DNS stand-in, `BRZL_PORTAL_HOST`.
3. **5d. Example app** — **done 2026-10-18** (RETROSPECTIVE; ADR-0034):
   `tzvat/chofesh` is a separate workload, its CI publishes the image, the
   follow policy picks the commit, `driver/access/github.sh` makes its
   credentials, INSTALL.md is the front door.
4. **6. Logs** — **done 2026-10-21** (RETROSPECTIVE; ADR-0027): the
   collector, the admin and diagnostic log stores, Grafana, UTC, the run
   output header, the API and store audit logs.
4a. **A credential on the collector's OTLP receiver** — **done 2026-10-22**
   (RETROSPECTIVE; Q163–Q166): mutual TLS from the store's CA.
5. **6a. Sign-on** — **done 2026-10-27** (RETROSPECTIVE, three entries;
   ADR-0035): Dex and oauth2-proxy in front of the portal, `kubectl`
   through Dex, the outside review's conditions taken on, the auth flows
   in SECURITY.md. Items 30 and 31 hold the rest of that review.
6. **6b. Break-glass mode** — **done 2026-10-28** (RETROSPECTIVE, two
   entries; ADR-0037): the record of each use, the audit rule, the alert,
   the reader of the admin log store (item 28). Also the local shape of
   items 23 and 29. The verbs are `open`, `apply`, `close` and the mode `audit`
   since item 37.
7. **6c. Cold storage** — **done 2026-10-28** (RETROSPECTIVE; ADR-0027
   amendment): the cold log store on the host, read with `jq`, the
   incident example in RECOVERY.md. The database backups moved to item 9.
8. **7. `promote platform`** — roll a platform revision one environment at a
   time (Q118).
9. **7h. Remote harness** — a second host (huginn, VMs on sleipnir, or
   OpenStack) to model a shared remote environment (Q116, deferred).
   **From pass 6c (Q217, 2026-10-28):** practise backup and restore here,
   because staging is closest to the case where they matter. The cold
   store becomes S3-compatible: the Versity S3 Gateway with its POSIX
   backend (Q210 (a)), or the substrate's own store. Then each workload's
   database backups through the Barman Cloud Plugin (Q211 (a)), and a
   restore drill that the user runs, with a runbook step (Q213 (a)). The
   collector's `awss3` exporter can write the cold records to the same
   store.
10. **8. Substrate adapters** — one pass for each: first the shared interface
    and AWS, then others. Open items for AWS: the secret-store adapter
    (Secrets Manager) and `gitops/clusters/{dev,prod}/secret-store/`; the
    ECR pull-through for `ghcr.io` needs an upstream credential (a GitHub
    token in Secrets Manager) before dev can pull the example app's image;
    the AWS runbooks and the legacy AWS scripts (`platform.sh`,
    `bootstrap-argocd.sh`, `seed-demo-data.sh`, the Terraform ingress) still
    name the demo-app and `gitops/operators/postgres`, where only the DR
    recovery artifacts remain; the
    `letsencrypt` TLS type (an ACME `ClusterIssuer` with DNS-01 at FreeDNS
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
   From pass 6c (Q217): chofesh's AWS overlay uses the in-tree
   `barmanObjectStore`, which CNPG 1.29 deprecates and 1.31 removes. Move
   it to the Barman Cloud Plugin (an `ObjectStore` and the plugin
   reference) before the operator reaches 1.31. The cold log store on AWS:
   the bucket, its lifecycle rule (Q212), and the collector's exporter.
   The environment definition's keys (Q250, the user, 2026-11-05). When
   the second substrate's file exists, decide the key names. Either a
   substrate-specific key carries the substrate's name
   (`BRZL_LOCAL_ZOT_PORT`), or the sections and the component prefix
   (`K3D`, `ZOT`, `OPENBAO`) are enough. Two readers cross the sections:
   the OpenBao adapter and audit
   mode read `BRZL_K3D_CLUSTER` (and the adapter `BRZL_DOCKER_NETWORK`).
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
13. **Argo CD upgrade and the sync switch** — **done 2026-11-04,
    user-accepted** (RETROSPECTIVE; ADR-0025 amendment): chart 10.11.6,
    annotation tracking, the NetworkPolicies on, `apply` on `argocd app
    sync --local`. The sync verbs folded into break-glass mode in item 37.
    The user said "fine for now" and looks at it again after the next
    passes.
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
    reading the fast-mode run sheet, now `break-glass apply`). Today the
    emitted groups wrap each rendered manifest in a `kubectl apply -f - <<EOF` heredoc. Clearer: the
    group writes the manifests as YAML files in `var/run/<env>/<run>/`, one
    object or one app per file. Then it applies them by file name, or
    `tee`s them in. Then an operator can read a manifest later on its own. The
    core style idea: the stream emits each manifest alone, so that a
    redirect puts it in a file. That is one more pipe segment in the
    driver's emitted actions. It is either a doctrine update in
    `ryderdain/bash` (STYLE §1.2, emitted groups) or a mistake here to
    correct against the doctrine. Decide with the doctrine's owner, then
    apply it to `modes/break-glass.sh` (`apply`) and the phases.
16. **Parked: `cluster run <phase>`** (ADR-0038 names it) — run one phase again on a
    finished cluster, with the conductor install in a phase of its own
    (Q130 b). **Only in case a later pass needs it**; certificate renewal
    does not (cert-manager, ADR-0036).
17. **`cluster state`: list the state kept outside the cluster**
    (proposed 2026-10-14 in the review of the design's shape, then Q161,
    2026-10-19). That state keeps growing, as Q66 intends. It holds the Zot
    cache, the OpenBao volume with its seal key and tokens, the local CA,
    the access files and the run directories. From pass 6 it also holds the
    admin log data, the collector's queue and the cold copy. Nothing
    lists all of it in one place. The command is a read-only generator: each item with its
    location, size and age, and the CA trust in the keychain as a reminder.
    The removal of each item stays a documented command in LOCAL.md.
18. **A purge for rapid teardown and cleanup** (user, Q161, 2026-10-19).
    Superseded by item 40, `cluster teardown all`.
19. **A low-memory mode** (user, Q158, 2026-10-19). The full local
    environment used 5.0 GiB with metrics and logs (pass 6, measured). huginn
    (8 GB) and other small machines cannot run it. A mode that turns off
    or shrinks the heavy parts with few design changes, built only when a
    need for it appears.
20. **Argo CD gives up after five failed syncs** — **done 2026-10-22**
    (RETROSPECTIVE; Q167, Q168): no retry limit, phase 40 names a failing
    Application, the alert `BrzlSyncFailing`.
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
    the first public-cloud environment. **Local decided 2026-10-28**
    (Q207): the kubeconfig stays for the life of the cluster.
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
27. **oauth2-proxy trusts `X-Forwarded-*` from any address** — **done
    2026-10-27** (pass 6b): a NetworkPolicy admits only the portal's pods,
    and phase 40 checks it.
28. **An emergency Grafana for the backed-up logs** — **built 2026-10-28**
    (pass 6b, ADR-0037): the reader of the admin log store, `audit
    bootstrap` and `audit teardown` since item 37.
29. **The driver is a machine identity in every scenario** (found
    2026-10-26, `notes/AUTH-FLOWS.md`). Every phase acts as
    `system:admin` (the kubeconfig) and as the store token `driver`. The
    API audit log and the store's audit log cannot name the person who
    ran a phase. Only the shell on the operator's machine knows. Step 2 of
    pass 6a (`kubectl` through Dex) names a person for `kubectl`, not for
    the phases. Decide with item 23 whether the driver should act with a
    person's identity on a public cloud. The store token `driver` is a
    standing credential of the same kind. OpenBao can issue a short-lived
    token for each run from a local auth method (review finding 5).
    **Local decided and built 2026-10-28** (Q208, Q209): each run
    output's header line names the account on the operator's machine,
    declared, not verified; the token `driver` stays. The cloud shape is
    pass 8, with item 23.
30. **Narrower `kubectl` roles for the tiers** (user, after the
    auth-flows review, 2026-10-26). Step 2 binds `brzl-auditors` and
    `brzl-operators` to the built-in `view` ClusterRole. `view` reads
    `pods/log` and ConfigMaps in every namespace, so an auditor reads the
    workloads' logs and their configuration (not Secrets). And `view`
    cannot `rollout restart`, so an operator restarts through Argo CD.
    Build: a narrower auditor ClusterRole. A read-only role for the
    people who develop one workload, limited to its namespace (with item
    24, the Grafana side). Decide the operator's `kubectl` rights.
31. **Image integrity** (review findings, 2026-10-26). Nodes pull from
    Zot over plain HTTP on the Docker network. Applications name tags, and
    nothing checks a signature or a digest. Zot could serve TLS with a
    certificate from the store's CA today. Then: digest pinning, or a
    signature policy (cosign). Branch protection on the workload's
    development branch is a control outside the platform. Name it as
    assumed in SECURITY.md.
32. **`kubectl` sign-in from a remote kiesei shell** (user, Q192,
    2026-10-27). The browser callback (Q187) needs the browser on the
    machine where `kubectl` runs, or an SSH port forward. When a remote
    shell exists, make kubelogin's grant type an environment value:
    `device-code` there (a URL and a short code, no callback), with a
    shorter refresh-token lifetime than local's 7 days, or none. The
    `argocd` CLI has no device flow; it keeps the callback.
33. **Dex's approval page on Argo CD's hourly re-login** — **done
    2026-10-27** (ADR-0035 "Corrections"): the gate's `approval_prompt`,
    and nginx dropped the refreshed cookie.
34. **Two sign-ins at once in one browser** (seen 2026-10-28, the live
    test of pass 6b). After a new cluster, an old Grafana tab and a new
    one started Grafana's sign-in at the same time. Grafana keeps one
    state cookie, so the first callback failed ("state did not match"),
    and Grafana showed its own page with an error. One click on its
    sign-in button continued. The gate had the same fault, fixed on the
    pass 6b branch (one CSRF cookie per sign-in). Grafana has no such
    setting. The option: Grafana reads the person from the gate's
    headers (`auth.proxy`) and has no sign-in of its own. That also
    helps item 26. A polish item: close old tabs after a new cluster.
35. **Rename `hold` / `release`** — dropped 2026-11-05 (Q234 b): the pair
    and the sync verbs were one thing. Superseded by item 37. The branch
    `item-35-rename-hold-release` is the user's to delete.
36. **Emitted run sheets: one command per line** — **done 2026-11-06**
    (RETROSPECTIVE, the rule in `ryderdain/bash` STYLE §1.2, `a5e8127`):
    the driver's run block and one line of phase 10 split, `error.sh`
    re-vendored, the pin moved.
37. **The driver grammar** — **done 2026-11-05** (RETROSPECTIVE; ADR-0038):
    `BRZL_ENV=<env> driver.sh <mode> <verb>`, the modes `cluster`,
    `break-glass`, `audit`, the teardown guard. Supersedes item 35.
38. **Environment names and the environment definition** — **done
    2026-11-05** (RETROSPECTIVE; ADR-0039): `dev`/`test`/`stage`/
    `production`, `BRZL_SUBSTRATE=local`, `env/dev.env`,
    `gitops/clusters/dev`, the bootstrap from zero.
39. **The kiesei image: a core stage and one stage per substrate** —
    **done 2026-11-05** (RETROSPECTIVE; ADR-0040): `kiesei:local` is
    1.13 GB unpacked, from 2.12 GB.
40. **`cluster teardown all`, and the CA and hosts setup again** (user,
    2026-11-05, after the bootstrap from zero). `cluster teardown` leaves
    the external pieces: the secret store, the registry cache, the
    collector, the DNS stand-in, the network and the log store. It also
    leaves the resolver entry and the CA in the operator's trust store.
    `teardown all` removes them too, in the manner of the item 38
    migration (an emit script, one group per piece, behind the guard;
    Q249). It states what it keeps: the access files, which take browser
    steps to make again, and `var/run/<env>` as the record. The host
    part is a host run sheet for removal, beside `10-host.sh`. With it,
    look at the CA and hosts setup once more. The trust step compares the
    fingerprint since 2026-11-05 (`91ca744`). But an old CA of the same
    name stays in the keychain. The NSS nickname is `brzl-<host>`. And
    `kiesei.sh` mounts the CA into the container by the host name. Takes
    the place of item 18 and the "removal" half of item 17.

Standing concerns (check in every pass):

- **GitHub App before leaving the local substrate** (Q61). The repo is private. Argo CD on
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

## Earlier plans (June 2026, before the local-first refactor)

The take-home's plan of 2026-06-10 had four items: an
automation-methodology overhaul against `notes/GUIDANCE.md`, a polish of
that guide, an environment realignment, and a multi-account CI design.
The first two became the Bash doctrine in `ryderdain/bash` (passes 0–1).
The third chose model B (one source per layer, per-environment tfvars and
backend; SPEC §3) and continues as item 10. The fourth is SPEC §9, with
item 10. The candidates carried over from the take-home folded into items
10, 15, 21 and 31, or were done in pass 1. The aroni threads of that time
live in the aroni vault's own BACKLOG. The full text of these sections is
in git history before 2026-11-05.
