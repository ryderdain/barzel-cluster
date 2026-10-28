# Runbook — Local-dev stack (k3d)

Run the platform and its example app on a developer laptop with **no AWS**
— the first environment of the promotion chain (ADR-0024,
[ARCHITECTURE](ARCHITECTURE.md)). The example app is
[chofesh](https://github.com/tzvat/chofesh) (ADR-0034): Argo CD reads
its manifests from that repo, and the platform's own manifests get a thin
[`gitops/clusters/local`](../gitops/clusters/local) overlay.

## Prerequisites

- A container engine (Docker Desktop, Colima, or equivalent), with the engine
  started, and its `docker` CLI.
- Internet access. The images come from the upstream registries, through the
  local Zot cache. Argo CD reads this repository and the workload's
  repository from GitHub.
- No AWS account, profile, or credentials.
- For a private workload: `gh`, the GitHub CLI, logged in to your account.
  The access script (below, "The workload's access") uses it.
- For fast mode only: the example app's checkout beside this repo,
  `git clone git@github.com:tzvat/chofesh.git ../chofesh`
  (`BRZL_EXAMPLE_APP_SRC` in `env/local.env`). Argo CD reads the pushed
  repo, not the checkout.
- Enough memory for the container engine. The reference hosts:

  | Host | Hardware | Note |
  | --- | --- | --- |
  | sleipnir | Apple M5, 10 cores, 32 GB | The main host. Docker Desktop's VM had 7.75 GiB on 2026-10-14; that is a setting, and you can increase it. |
  | huginn | Apple M2, 8 cores, 8 GB | Tight for the full stack. |

  The full environment, with metrics and logs, used 5.0 GiB on sleipnir
  (measured 2026-10-21, pass 6). The k3d node used 4.7 GiB, and the
  containers beside it (the collector, OpenBao, Zot, DNS, the load
  balancer) used 0.3 GiB together. Give
  the engine's VM at least 8 GiB. huginn cannot run the full environment
  until a low-memory mode exists (BACKLOG 19).

The other tools (`k3d`, `kubectl`, `helm`, `jq`) are in the kiesei image. Make
the image one time, and again after a change to `containers/kiesei/`:

```sh
docker build -t kiesei:local containers/kiesei
```

## Where the procedure operates

The driver prints a procedure. The command on the right side of the pipe
selects where it operates:

- `| bash driver/kiesei.sh` operates it in the kiesei image, with the pinned
  tools. This is the usual selection.
- `| bash` operates it on the host. Then the host must have `k3d`, `kubectl`,
  `helm`, `jq` and `yq`. Without one of them, a phase cannot be emitted,
  and the driver stops with a message that says so.

The procedure is the same for the two shells.

## Up

The driver prints a procedure and does not operate it. You give your approval
when you pipe the procedure to a shell.

Careful mode, one phase at a time:

```sh
bash driver/driver.sh local next                          # read the next phase
bash driver/driver.sh local next | bash driver/kiesei.sh  # operate it; do again
```

All phases that are not complete, at once (only for effects on this machine):

```sh
bash driver/driver.sh local up | bash driver/kiesei.sh
```

Argo CD reads this repository, which is private. The first time, give the
driver the read-only deploy key: phase `25-bootstrap` writes it into the
cluster secret store, and the store keeps it. Later runs do not need the key.
Give it only to the command that operates the procedure. The key is then not
in your shell for other commands:

```sh
bash driver/driver.sh local up \
  | BRZL_REPO_DEPLOY_KEY="$(<~/.ssh/sleipnir-brzl-deploy)" bash driver/kiesei.sh
```

The run sheet records only the name `BRZL_REPO_DEPLOY_KEY`, not the key. The key
must not have a passphrase, because Argo CD cannot use one. Before an
environment other than local, a GitHub App replaces the deploy key (BACKLOG).

The local environment has five phases. Each phase has a locus: the driver
(where you operate the procedure) or the conductor (a kiesei pod in the
cluster). The locus is where the run sheet of the phase runs. The command is
always `driver.sh`, for all phases: the driver sends a conductor phase to the
conductor. Do not operate `driver/conductor.sh` yourself.

- `10-substrate` (driver) makes the containers beside the cluster: the Zot
  registry, the OpenBao secret store and its CA, the DNS stand-in and the
  log collector. It issues the log collector's client certificate. Then it
  writes the kube-API's trust in Dex (`apiserver/authentication-config.yaml`
  in the run directory). It makes the k3d cluster, with the portal's host
  name mapped to the portal's fixed address on the node and in CoreDNS. It
  writes the two kubeconfigs to the run directory: cluster-admin, and
  sign-on through Dex. It writes the host run sheet (below, "Steps on your
  machine"). If `k3d cluster create` waits at "Starting node" for more than
  a minute, the API server did not start: look at
  `docker logs k3d-brzl-local-server-0`, stop the stream, and run `down`.
  If the configuration of a container changed, it replaces that container.
  The data stays.
- `20-images` (driver) pushes the kiesei image to Zot. A workload's image
  is its own: its CI publishes it, and the cluster pulls it through Zot
  like every upstream image (ADR-0034).
- `25-bootstrap` (driver) connects the secret store to the cluster (the
  auth roles for External Secrets and cert-manager, the PKI role `portal`).
  It writes into the store, one time, the deploy key when you give it, the
  workload's access files, Grafana's admin password and the sign-on entries
  (below, "Sign-on"). Then it writes the
  Argo CD repository Secrets and Zot's upstream credentials from the store,
  and starts the conductor in the namespace `brzl-system`.
- `30-gitops` (conductor) installs Argo CD and applies the platform
  ApplicationSet (ADR-0025). Argo CD then deploys the platform from git:
  CloudNativePG, External Secrets, cert-manager, sign-on (Dex, oauth2-proxy)
  and the admin portal. It also deploys the metrics (kube-prometheus-stack
  with Grafana), the two log stores, the log collector, and the example app
  with its Postgres.
- `40-workloads` (conductor) waits until all Applications are Synced and
  Healthy, and checks the example app, its Postgres and the portal. It also
  checks that the smoke value from phase 25 came back through External
  Secrets. Then it checks that each log source arrived in its log store,
  and the parts of sign-on: the portal sends a request without a session
  to sign in, Dex answers at the issuer URL, and Argo CD names it.

Argo CD follows the branch that is checked out when phase `30-gitops` is
emitted. To follow a different branch, export `BRZL_GITOPS_REVISION`. Argo CD
reads only commits that are pushed: the phase shows a warning when your branch
is ahead of its remote.

For a conductor phase, the driver copies the run sheet into the conductor pod,
operates it there, shows its output, and copies back the exit status. The
run goes on in the conductor if you stop the driver with Ctrl-C. When you
run the phase again while that run goes on, the driver follows it, and
starts no second run. The
conductor stops itself after `BRZL_CONDUCTOR_IDLE_SECONDS` with no work. The
next conductor phase starts it again.

Each phase writes a run sheet to `var/run/local/cluster-<UTC>Z/`, for
example `cluster-20261019T1300Z`: the commands (`<NN>-<phase>.sh`), their
output (`.out`), the exit status (`.rc`), and `.ok` when the check of the
phase is correct. A `down` writes to `teardown-<UTC>Z`. Each output starts
with a header line that names the environment, the run, the phase and the
start time. The admin log store receives every output (below, "The logs").
If a phase stops, repair the cause and
operate `up` or `next` again. The driver starts at the first phase that has no
`.ok`.

To see the commands of one phase without the driver:

```sh
bash driver/phases/30-gitops.sh phase_up local var/run/local/preview
```

To see the condition of the current run:

```sh
bash driver/driver.sh local status
```

The values for the local environment are in `env/local.env`. To change one
value for one run, export it. The driver shows a warning and records the
value in the run sheet. Export the value. Then the two sides of the pipe get
it:

```sh
export BRZL_K3D_AGENTS=2
bash driver/driver.sh local up | bash driver/kiesei.sh
```

### The Zot registry

Zot operates adjacent to the cluster, on the container network `brzl-local`.
It is a pull-through cache for `docker.io`, `ghcr.io`, `quay.io`,
`registry.k8s.io` and `public.ecr.aws`, and the
registry for images that you assemble here
(`localhost:5001/brzl/...`). Its data is on the volume `brzl-zot-data`. Thus the
cache stays when you remove the cluster. The first pull of an image through
Zot can continue for some minutes.

To remove Zot, its cache, and the network:

```sh
docker rm -f brzl-zot
docker volume rm brzl-zot-data
docker network rm brzl-local
```

### The secret store

OpenBao is the local cluster secret store (ADR-0026). It mimics a cloud secret
store: it operates adjacent to the cluster, on the network `brzl-local`, with
its data on the volume `brzl-openbao-data`. It exists before the cluster and
stays when you remove the cluster. The driver reaches it at `127.0.0.1:8200`.
In the cluster, External Secrets reads it through the store `brzl-secrets`.

The files in `var/secret-store/local/` are your credential to the store.
Phase 10 makes them the first time. They are not in git:

- `seal.key`: the key that unseals the store. If you lose this file, the
  store is lost. Purge it and start again.
- `driver.token`: the token the driver writes with.
- `recovery.key`: to make a new root token if `driver.token` is lost.
- `ca.crt` (not a credential): the certificate of the CA that the store is
  for the admin portal and the log intake (ADR-0036). Phase 10 writes it.
- `log-shipper/`: the client certificate and key of the collector beside
  the cluster (below, "The logs"). Phase 10 issues them on every run.

A store made before 2026-10-15 has a driver token without the PKI
capabilities. The check of phase 25 says so; purge the store (below) and
run `up` again.

### The logs

The logs go to two log stores (ADR-0027), both Loki in the cluster, in the
namespace `logs`:

- **The admin log store** (`log-store-admin`) keeps the records that audit
  the environment. These are the run outputs, the k3s server log, the
  Kubernetes API audit log (metadata only), the secret store's audit log
  and the Kubernetes events. Its data is in the host
  directory `var/log-store/local/admin/`, so it stays when you remove the
  cluster. It saves its records within five minutes.
- **The diagnostic log store** (`log-store-diagnostic`) keeps the pod logs
  of the workloads and the platform applications. Its data is lost with
  the cluster.

A namespace chooses where its pod logs go with the annotation
`brzl.dev/log-routes` (`drop`, `admin`, `diagnostic`, `cold`), and how long
they stay with `brzl.dev/log-retention` (`7d`, `30d`, `90d`). With no
annotation, its logs go to the diagnostic log store for 7 days. `cold` has
no destination before pass 6c.

Two collectors send the records. A collector in the cluster, on each node,
reads the pod logs, the k3s server log, the API audit log and the events. A
collector beside the cluster, the container `brzl-log-collector`, reads what
only your machine has: the run outputs in `var/run/local/` and the secret
store's audit log in `var/log-store/local/openbao-audit/`. It sends them to
the collector in the cluster. While there is no cluster, it keeps them in
its queue in `var/log-store/local/queue/` and sends them later. So the
records of phases 10 to 30 and of a `down` arrive after the next `up`. Like
Zot, it stays when you remove the cluster.

The two collectors use mutual TLS (BACKLOG 4a). The receiver in the cluster
is `log-intake.<host>`, with a certificate from cert-manager. It accepts
only the client certificate in `var/secret-store/local/log-shipper/`, which
phase 10 issues from the store's CA, valid for 30 days. A cluster that
lives longer than that keeps its run outputs in the queue until the next
`up` issues a new certificate. No workload can write over OTLP.

To read the logs, open Grafana in the portal (`/grafana/`), then Explore.
Choose the data source "Admin log store" or "Diagnostic log store". Some
queries:

```text
{brzl_source="run-output", brzl_phase="25-bootstrap"}
{brzl_source="api-audit"} |= "secrets"
{k8s_namespace_name="chofesh"}
```

When the cluster is down or gone, use the reader of the admin log store
([BREAK-GLASS.md](BREAK-GLASS.md)). It gives the same data source on
`http://127.0.0.1:3300/explore`, with no sign-on. It shows only what is in the store.
The run outputs of a `down`, and of every action while there is no
cluster, are still in the queue:

```sh
bash driver/driver.sh local reader_on | bash driver/kiesei.sh
bash driver/driver.sh local reader_off | bash driver/kiesei.sh
```

To remove the collector beside the cluster and all log data that is kept
outside the cluster (the admin log store's data, the queue and the store's
audit log):

```sh
docker rm -f brzl-log-collector
rm -r var/log-store/local
```

### The workload's access

The example app is a private repository under a GitHub organization, and
its image a private package (ADR-0034). Two credentials let the platform
read them, both read-only. A GitHub App on the organization serves Argo CD
and the ApplicationSet's SCM generator. A token with `read:packages` serves
Zot's pull-through of the image. `driver/access/github.sh` makes them with
your `gh` login, one step at a time, and leaves six files in
`var/access/github/<org>/` (not in git). The steps and the table of the
six files are in [INSTALL.md](INSTALL.md), section 4.

Phase 25 reads those files once and puts them into the store. From the
store it writes the Argo CD `repo-creds` Secret `workload-github-app`, for
`https://github.com/<org>` and so for every repository of the organization.
It also writes Zot's upstream credentials file,
`var/secret-store/local/zot-credentials.json`.
It restarts Zot when that file changed. Later runs need the files no more.
A public workload needs none of this: the phase says so and goes on.

To write one secret into the store yourself, use the `bao` CLI in the
container. The value goes on stdin, and the token in the environment:

```sh
printf '%s' "$VALUE" | BAO_TOKEN="$(<var/secret-store/local/driver.token)" \
  docker exec -i -e BAO_TOKEN -e BAO_ADDR=http://127.0.0.1:8200 brzl-openbao \
  bao kv put -mount=secret <path> value=-
```

To purge the store and its credential, and start from zero:

```sh
docker rm -f brzl-openbao
docker volume rm brzl-openbao-data
rm -r var/secret-store/local
```

The next `up` makes a new store. Then give the deploy key again.

## Use it

**When a sync keeps failing.** Argo CD tries a failed sync again with no
limit, at most every 3 minutes. So a passing fault heals by itself. Phase
40 prints a warning, with the error, for an Application that failed 3
times or more. At other times, Grafana's alert list shows
`BrzlSyncFailing`: a warning at 3 failed attempts, critical at 5. Nothing
sends the alert to you yet (BACKLOG 21).

The admin portal is the one place to start: `https://<host>/` (ADR-0028).
It links to Argo CD (`/argocd/`), Grafana (`/grafana/`) and the example
app (`/apps/chofesh/`), and lists the CLI commands. You sign in with
GitHub first (below, "Sign-on"). The host name and the port
are in `env/local.env` (`BRZL_PORTAL_HOST`, `BRZL_PORTAL_PORT`). The k3d
adapter maps the port to the portal's NodePort when it makes the cluster.

**The host name** (ADR-0036). `env/local.env` sets `local.barzel.sh`, the
reference setup on sleipnir. A DNS stand-in beside the cluster answers for
that one name, and your machine must ask it (below, "Steps on your
machine"). For a first test without that step, export
`BRZL_PORTAL_HOST=brzl-local.localhost`: every `*.localhost` name resolves
to `127.0.0.1` on macOS and in browsers, and no DNS stand-in runs.

You sign in with GitHub (below, "Sign-on"). Argo CD and Grafana have no
built-in admin login.

The CLI tools are in the kiesei image ([docs/guide/kiesei.md](guide/kiesei.md)):

```sh
bash driver/kiesei.sh shell   # signs you in through Dex: kubelogin prints a URL, open it
kubectl get nodes             # as yourself
argocd app list               # the first use signs in through Dex too
# in an emergency, without sign-on: the cluster-admin kubeconfig, named on purpose
KUBECONFIG=var/run/local/current/kubeconfig argocd --core app list
```

**In the shell you are yourself** (sign-on step 2, Q193). The run
directory holds two kubeconfigs. `kubeconfig-sign-on` signs you in
through Dex with kubelogin: the shell sets `KUBECONFIG` to it, and signs
you in at its start when no session is cached. kubelogin keeps your
tokens in `oidc-cache/` beside it and refreshes them without a step, for
7 days, or until Dex restarts. The kube-API names you `oidc:<login>`, and
your team gives your rights: `brzl-admins` everything, the other two
tiers the built-in `view` role. `argocd` keeps its session in
`argocd-config` there, from `argocd login --sso` on its first use, and
signs in again after an authentication error. The other file,
`kubeconfig`, is `cluster-admin`: the driver's, and the emergency path
when Dex or GitHub is down. On your own machine, the same two files work
with kubelogin and the CLIs installed there (`brew install
int128/kubelogin/kubelogin`).

Both sign-ins wait for a callback in your browser (`localhost:8000`,
`localhost:8085`), so the container must share the host's network. On
Docker Desktop that is a setting: Settings, Resources, Network, "Enable
host networking" (4.34 and later). Without it, kiesei is in Docker
Desktop's VM, which is enough for the driver (the k3d ports are published
there) but not for a callback: the browser gets "connection refused"
(seen 2026-10-27). With it, the Mac reaches every port a container
binds, loopback included.

k3d also adds the cluster to your default kubeconfig, as the context
`k3d-brzl-local`.

Do a search. The app sends the query to Sefaria, shows the results, and writes
them to the local Postgres, as in the cloud.

### Steps on your machine

Two steps change your machine, not kiesei. You do them one time, and only
for a local environment on a laptop. The entries stay across `down` and
`up`.

1. **Resolve the name** (only for a chosen name, not for `*.localhost`).
   The DNS stand-in answers `local.barzel.sh` with `127.0.0.1` on
   `127.0.0.1:1053`. On macOS, tell the system to ask it for that name
   only. The directory `/etc/resolver` is macOS's own, and the name of the
   file in it must be the host name:

   ```sh
   sudo mkdir -p /etc/resolver
   printf 'nameserver 127.0.0.1\nport 1053\n' \
     | sudo tee /etc/resolver/local.barzel.sh
   ```

   On Linux, add `127.0.0.1 local.barzel.sh` to `/etc/hosts` instead.
2. **Trust the CA.** The store is the CA (`local-ca` mode), and its
   certificate is `var/secret-store/local/ca.crt`. Until you trust it, the
   browser warns, and that is acceptable. The commands depend on the
   operating system. The Linux rows were tested in containers on
   2026-10-23:

   | System | Commands |
   | --- | --- |
   | macOS | `security add-trusted-cert -r trustRoot -k ~/Library/Keychains/login.keychain-db var/secret-store/local/ca.crt` (no `sudo`; macOS asks for your password) |
   | Debian, Ubuntu, Alpine | `sudo cp var/secret-store/local/ca.crt /usr/local/share/ca-certificates/brzl-local.barzel.sh.crt` (the name must end in `.crt`), then `sudo update-ca-certificates` |
   | Fedora, RHEL | `sudo cp var/secret-store/local/ca.crt /etc/pki/ca-trust/source/anchors/brzl-local.barzel.sh.crt`, then `sudo update-ca-trust` |
   | openSUSE | `sudo cp var/secret-store/local/ca.crt /etc/pki/trust/anchors/brzl-local.barzel.sh.crt`, then `sudo update-ca-certificates` |
   | Arch | `sudo trust anchor --store var/secret-store/local/ca.crt` |

   No one command works on all Linux systems: `trust anchor` fails on
   Ubuntu. On Linux, Firefox and Chrome usually keep their own certificate
   store (NSS) and do not read the system's. To trust the CA there too,
   use `certutil` from the NSS tools:
   `certutil -d sql:$HOME/.pki/nssdb -A -t C,, -n brzl-local -i
   var/secret-store/local/ca.crt` (for Chrome, not tested here).
   Firefox has a store in each profile. Windows is not a supported driver
   machine.

**The host run sheet (Q180).** Phase 10 writes the steps into
`var/run/local/current/10-host.sh`. When the stream ends,
`driver/kiesei.sh` runs that sheet on your machine, outside kiesei. The
sheet finds which steps are not done, for your system (`/etc/os-release` on
Linux). It shows them, asks you one time to confirm, and runs them with
`sudo`. When all are done, it asks nothing. Its output and exit status go
beside it (`10-host.out`, `10-host.rc`), and the admin log store receives
the output. It runs again only when phase 10 writes it again. Without a
terminal, or with `| bash` in place of `| bash driver/kiesei.sh`, run it
yourself: `bash var/run/local/current/10-host.sh`. The checks of phases 10
and 25 name the sheet. The purge (BACKLOG 18) removes the entries.

**What sign-on changes here: nothing.** Dex is at `/dex/` under the portal
host (Q172), so your machine needs no other name. The log intake's name,
`log-intake.<host>`, is used only between the containers. For `kubectl`
through Dex, the k3s server resolves the portal's host name through its
own hosts file, which phase 10 sets: nothing on your machine.

## How a change to the example app arrives

The example app's repo has a contract with the platform (ADR-0034,
amendment): `main` is its development branch, and its CI publishes an
image for every push to it. The local environment **follows the branch**
(`BRZL_WORKLOAD_FOLLOW=branch`). The platform ApplicationSet asks GitHub
for the head commit of `main` every 5 minutes. Argo CD then deploys that
commit's manifests with that commit's image. So, in GitOps mode:

1. Push to `main` of `tzvat/chofesh`. CI builds the image for both
   architectures, about 3 minutes.
2. Within 5 minutes, Argo CD shows `chofesh` at the new commit, and the
   pods roll to `localhost:5001/ghcr.io/tzvat/chofesh:<commit>`, pulled
   through Zot from `ghcr.io`.

A manifest change arrives the same way. The other environments follow a
release instead (`release`): the tag the ApplicationSet element names,
made in the app's repo with `make release`.

For a change you have not pushed, use fast mode (below) with
`make dev-image` in the checkout. It builds for this machine, pushes to
Zot's push namespace, and points `deploy/local` at the build.

## Fast mode

Fast mode is for changes to the structure of the cluster: you apply your
working tree directly and do not push first. Argo CD holds while fast mode is
on. Fast mode is only for the local environment. For an emergency in any
environment, use break-glass mode ([BREAK-GLASS.md](BREAK-GLASS.md)).
Fast mode refuses to run during a hold.

```sh
bash driver/driver.sh local fast_on  | bash driver/kiesei.sh  # Argo CD holds
bash driver/driver.sh local apply    | bash driver/kiesei.sh  # working tree
bash driver/driver.sh local fast_off | bash driver/kiesei.sh  # pushed branch
```

- `fast_on` sets the annotation `brzl.dev/auto-sync: "false"` on the cluster
  Secret. The ApplicationSet then removes automated sync from each
  Application. No commit is necessary.
- `apply` renders the kustomize apps from your working tree, with the same
  images and patches that Argo CD injects. The example app renders from its
  checkout beside this repo (`BRZL_EXAMPLE_APP_SRC`). The conductor applies
  the result. So the loop for the app is: edit `../chofesh`, then, when the
  code changed, `make dev-image` there, then `apply`, look. `make dev-image`
  points `deploy/local` at the build. `git checkout deploy/local` undoes
  that before a commit.

  The helm apps (Argo CD, CloudNativePG, External Secrets, cert-manager)
  are not included: to change one, push a branch and let Argo CD sync it.
- While fast mode is on, Argo CD shows each changed Application as OutOfSync.
  The difference is your change compared with the pushed branch.

**Caution:**

- `fast_off` makes the cluster agree with the pushed branch again. Argo CD
  prunes and heals. **A change that you did not commit and push is removed
  from the cluster.** Push it before `fast_off`.
- `apply` refuses to operate when fast mode is off. Otherwise Argo CD would
  revert the change at once.
- Phase `40-workloads` fails while fast mode is on, because Argo CD does not
  sync. Operate `fast_off` before you operate `up` again.
- Do not use **Sync** in the Argo CD UI while fast mode is on. A manual sync
  replaces your working-tree change in that Application with the pushed
  branch. Use **Refresh** to see the current difference: Argo CD compares
  only every 3 minutes by itself.

## Retire an Application

The platform ApplicationSet never deletes an Application (ADR-0025). When
an element leaves `gitops/platform/applicationset.yaml`, its Application
stays, and phase 30 stops before it applies the file ("Application(s) …
have no element in the new ApplicationSet"). Remove it on purpose, in this
order. The order matters: while the element is still in the ApplicationSet
in the cluster, a deleted Application comes back at once.

```sh
export KUBECONFIG=var/run/local/current/kubeconfig

# 1. Find the element's index in the ApplicationSet in the cluster.
kubectl -n argocd get applicationset brzl-platform -o \
  jsonpath='{.spec.generators[0].matrix.generators[1].list.elements[*].appName}'

# 2. Drop the element (index N; drop the highest index first when there are several).
kubectl -n argocd patch applicationset brzl-platform --type json \
  -p '[{"op":"remove","path":"/spec/generators/0/matrix/generators/1/list/elements/N"}]'

# 3. Delete the Application. Its finalizer removes what it deployed; the
#    namespace takes the rest (the Application does not own the namespace).
kubectl -n argocd delete application <name>
kubectl delete namespace <namespace>

# 4. Apply the file: phase 30 runs again, then phase 40.
rm var/run/local/current/30-gitops.ok
bash driver/driver.sh local up | bash driver/kiesei.sh
```

Step 4 removes the `.ok` by hand because `up` skips a phase that has one
(BACKLOG item 16 is the driver action for this).

## Sign-on

Every environment has sign-on (ADR-0035, Q169–Q183). The flows are in
[SECURITY.md](SECURITY.md):

- nginx in the portal asks oauth2-proxy about each request. Without a
  session, the browser goes to Dex at `/dex/`, and Dex sends it to GitHub.
- Only members of three teams in the organization pass:
  `brzl-admins`, `brzl-operators` and `brzl-auditors` (GLOSSARY, "Access
  tier"). Each environment decides what each tier may do.
- Argo CD and Grafana each sign in to Dex themselves and map the teams to
  their roles. In Argo CD, press "Log in via GitHub". Grafana signs you in
  at once. Their built-in `admin` logins are off.
- The workloads (`/apps/<workload>/`) are outside sign-on.
- In the cluster, the portal's host name is the portal's Service (a rule in
  k3s's CoreDNS, phase 10), and on the node it is the portal's fixed
  Service address (`BRZL_PORTAL_CLUSTER_IP`, a script that k3d runs at
  every start of the node). So the pods and the kube-API reach Dex at the
  same URL as your browser. The fixed address is local only, a stand-in for public DNS
  (`gitops/clusters/local/portal/`). It is `10.43.0.43`: k3s's Service
  range is `10.43.0.0/16`, and Kubernetes keeps the first 256 addresses
  of it for fixed addresses, so nothing else takes it. A Service's address
  cannot change: a cluster from before it needs `down`, then `up`.
- `kubectl` signs in through Dex too (above, "Use it"). The kube-API's trust
  in Dex is a file that phase 10 writes (`apiserver/authentication-config.yaml`
  in the run directory) and the node mounts. Its path is set when the
  cluster is made: **a cluster from before step 2 needs `down`, then
  `up`**.
- Sessions end within an hour of a removal from a team: the gate, Grafana
  and kubelogin refresh their tokens every hour, and Dex refuses the
  refresh. Argo CD's UI asks for "Log in via GitHub" again every hour.

[SECURITY.md](SECURITY.md) tells what GitHub gives Dex at sign-in. Read it
before you try the platform with your own account.

**Before the first `up` with sign-on**, do these one time (gh logged in,
with the `admin:org` scope). `BRZL_SIGN_ON_ORG` in `env/local.env` names
the organization:

```sh
# the three teams; you in brzl-admins
bash driver/access/github.sh teams tzvat | bash
# the OAuth App, in the browser
bash driver/access/github.sh oauth_app tzvat local | bash
# verify
bash driver/access/github.sh sign_on_check tzvat local
```

The second step opens GitHub's form for a new OAuth App and prints the
values to type in. The callback URL is `https://<host>/dex/callback`. Then
it tells you how to put the client id and secret into
`var/access/github/tzvat/`. Phase 25 puts them into the store and stops if
they are absent.

**In an emergency** (Dex or GitHub fails), use the CLI with the
kubeconfig: `kubectl`, `argocd --core`, or a port-forward. A change to the
cluster in that state is a break-glass hold with a declared name
([BREAK-GLASS.md](BREAK-GLASS.md), "When Dex is down").

## Down

```sh
bash driver/driver.sh local down                          # read the procedure
bash driver/driver.sh local down | bash driver/kiesei.sh  # remove the cluster
```

This removes the k3d cluster only. The containers beside it (Zot, OpenBao,
the DNS stand-in, the log collector) stay, with their data, and so do the
admin log store's data and the steps on your machine. The next `up` starts
a new run.

## What differs from the AWS cluster (and why)

The example app's local overlay (`deploy/local` in its repo) touches only
the AWS-specific parts. All else is the same manifests as the cloud:

| Concern | AWS cluster | Local (k3d) | Why |
| ------- | ----------- | ----------- | --- |
| Images | ECR + pull-through (host and prefixes injected by the ApplicationSet) | Zot pull-through (host `localhost:5001`, the upstream name as prefix); the example app's image comes from `ghcr.io` the same way | same `host/prefix/path` shape as the cloud; no registry auth locally |
| Storage | EBS CSI, `gp3` | `local-path` (k3d built-in) | no cloud block storage on a laptop |
| Postgres | 3 instances (HA) | 1 instance | laptop footprint; HA isn't the point locally |
| Backups | CNPG → S3 (Barman) | **off** | no object store locally |
| Monitoring | kube-prometheus-stack | the same; the node exporter has no root file-system metrics | the k3d node is a container (`values-local.yaml`) |
| Logs | admin log store data in S3 (pass 8) | admin log store data in a host directory; a collector beside the cluster sends the run outputs | no object store locally; the driver's machine holds the run outputs |
| GitOps | the platform ApplicationSet (ADR-0025) | the same ApplicationSet; **fast mode** applies the working tree directly | one file for every environment |
| Sign-on | the same Dex and oauth2-proxy behind the portal (pass 8) | Dex and oauth2-proxy behind the portal; on the nodes and in the cluster, a host alias makes the portal's host name the portal's fixed Service address | one sign-on on every substrate; only the entry point differs (ADR-0035) |
| Certificates | `letsencrypt` mode (ACME DNS-01) | `local-ca` mode: OpenBao is the CA | a laptop needs nothing public (ADR-0036) |

**Image strategy.** The cluster pulls every image, the example app's
included, through Zot's cache, as a cloud cluster pulls through ECR
(ADR-0023). There is no ECR login and no registry credential. Only the
kiesei image and `make dev-image` builds are pushed to Zot directly, into
its push namespace `brzl/`.

**Parity note.** The CNPG operator, External Secrets, cert-manager, the
portal, the app's `Cluster` and its Deployment/Service are the same objects
as production. So a green local run is real evidence that the stack is
substrate-portable, not a bespoke laptop variant.
