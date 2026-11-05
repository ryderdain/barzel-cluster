# kiesei — a guide for this repo

*Draft (2026-10-15). Part of the guidebook: one file for each tool that
barzel-cluster uses. The documentation run after the last passes completes
it.*

## What kiesei is

kiesei is the container image that holds every tool the platform is
operated with, at pinned versions: `kubectl`, `kubelogin`, `helm`, `k3d`,
`argocd`, the
CNPG plugin, `tofu`, `ansible`, `yq`, `jq`, `aws`, and more. The word is
Hebrew for a toolbox (GLOSSARY). Your machine needs only a container engine
and its `docker` CLI. It does not need any of these tools.

The image runs in two places, which the GLOSSARY calls loci:

- **The driver**, on your machine: `driver/kiesei.sh` runs a procedure that
  the driver prints.
- **The conductor**, in the cluster: the same image as a warm pod, which
  runs the run sheets of the phases whose locus is the cluster (ADR-0021).

This guide is about the first.

## The basics

**A procedure arrives on stdin.** The driver is an emit script: it prints
the commands and runs nothing. The command on the right side of the pipe
decides where the commands run:

```sh
BRZL_ENV=local bash driver/driver.sh cluster bootstrap                           # read it
BRZL_ENV=local bash driver/driver.sh cluster bootstrap | bash driver/kiesei.sh   # run it in kiesei
BRZL_ENV=local bash driver/driver.sh cluster bootstrap | bash                    # run it on the host
```

The procedure is the same in each case, so the run sheets in `var/run/` are
the record of what ran, wherever it ran.

**What the container shares with your machine.** `kiesei.sh` starts the
image with:

- The engine's socket, so `docker` and `k3d` inside drive the engine on your
  machine.
- The host network, so the cluster API (`127.0.0.1:6550`) and every
  published port (Zot, OpenBao, the portal) are reachable with the same
  addresses.
- The repository, mounted at its own path. Each path in a procedure is then
  the same inside and out, and run sheets land in your `var/run/`.
- Every exported `BRZL_*` variable, so a one-off override or a bootstrap
  secret source (`BRZL_REPO_DEPLOY_KEY`) reaches the phase that needs it.
- The admin portal's host name, mapped to `127.0.0.1`, so the CLI tools
  reach the portal without DNS inside the container.
- `BRZL_HOST_OS`, the operating system of your machine, so a check can
  print a one-time step in the right form.
- `BRZL_HOST_USER`, your account on your machine, so each run output
  names you (`person=` in its header line). In the container, the account
  is root.

```text
 your machine                         kiesei container (same image as the conductor)
 ┌───────────────────────┐            ┌──────────────────────────────────────┐
 │ driver.sh ──stdin────────────────▶ │ bash: runs the procedure             │
 │ engine socket ─────────────────────│ docker, k3d                          │
 │ 127.0.0.1:<ports> ────host net─────│ kubectl, argocd, curl, bao (docker)  │
 │ the repository ────mount───────────│ /…/barzel-cluster (run sheets, env)  │
 │ BRZL_* exports ────────────────────│ the phases' inputs                   │
 └───────────────────────┘            └──────────────────────────────────────┘
```

**An interactive shell.** `bash driver/kiesei.sh shell` opens a shell in
the same container, with the same mounts and network. Use it for the CLI
tools that the admin portal lists, instead of installing them on your
machine.

## Use cases

Open the shell once, then:

```sh
bash driver/kiesei.sh shell
# kubectl is you: the shell uses the sign-on kubeconfig of the current run
# and signs in through Dex at its start (the browser opens on localhost:8000)
kubectl auth whoami
# only in an open break-glass when Dex is down (docs/BREAK-GLASS.md):
# kubectl as cluster-admin, with a red prompt, then back to you
as_admin
as_me

# Argo CD, through the portal, signed in with GitHub: open the URL it
# prints (the callback on localhost:8085 needs the host's network)
argocd login local.barzel.sh --grpc-web-root-path argocd --sso --sso-launch-browser=false
argocd app list
# in an emergency, without sign-on
argocd --core app list
argocd app diff portal

# the cluster
kubectl get applications -n argocd
kubectl -n portal describe certificate portal

# Postgres, with the CNPG plugin
kubectl cnpg status -n chofesh pg

# the secret store (the CLI runs in the store's container; the token is a file)
BAO_TOKEN="$(<var/secret-store/local/driver.token)" \
  docker exec -e BAO_TOKEN -e BAO_ADDR=http://127.0.0.1:8200 brzl-openbao bao status

# what a phase would run, without running it
bash driver/phases/30-gitops.sh phase_up local var/run/local/current
```

One-off commands need no shell. The container reads commands on stdin:

```sh
printf 'argocd version --client\n' | bash driver/kiesei.sh
```

## Where it comes from

`containers/kiesei/Dockerfile` pins each tool's version and verifies what
it downloads (ADR-0007, the supply-chain rule in SPEC §3). Phase 20-images
builds the image and pushes it to the environment's registry, where the
conductor pulls it. Build it once on your machine, and again after a change
to `containers/kiesei/`:

```sh
docker build -t kiesei:local containers/kiesei
```

## Where to read more

- The driver and its loci: [docs/LOCAL.md](../LOCAL.md), ADR-0021,
  ADR-0022.
- The image's contents: `containers/kiesei/Dockerfile`.
