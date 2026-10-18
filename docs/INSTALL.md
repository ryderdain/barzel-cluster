# Install — the local environment, from zero

This is the shortest path from a clean machine to the platform running on
it, with its example app. It is a procedure. The reference for each part is
[`LOCAL.md`](LOCAL.md). The design is in [`ARCHITECTURE.md`](ARCHITECTURE.md).

## 1. What the machine needs

- A container engine with its `docker` CLI (Docker Desktop, Colima or an
  equivalent), started, with at least 8 GiB for its VM.
- `git`, `bash` 4 or later, `jq`, `curl`.
- `gh`, the GitHub CLI, logged in to your account (`gh auth login`). The
  workload's access (section 4) uses it.
- Internet access. Images come from the upstream registries through a local
  cache, and GitHub answers the platform's reads.
- No cloud account and no credentials of a provider.

## 2. The repositories

```sh
git clone git@github.com:ryderdain/barzel-cluster.git
git clone git@github.com:tzvat/chofesh.git            # the example app, beside it
cd barzel-cluster
docker build -t kiesei:local containers/kiesei       # the toolchain image
```

The example app's checkout is for fast mode only (LOCAL.md). Argo CD reads
the pushed repository, not the checkout.

## 3. The platform's own deploy key

Argo CD reads this repository with a read-only deploy key. Make one for
your clone of it and register it on GitHub:

```sh
ssh-keygen -t ed25519 -N '' -C brzl-local -f ~/.ssh/brzl-local-deploy
gh repo deploy-key add ~/.ssh/brzl-local-deploy.pub --title brzl-local
```

The key is given to the first `up` only (section 5). The cluster secret
store keeps it after that.

## 4. The workload's access

The example app is a private repository under a GitHub organization, and
its image is a private package. The platform reads both with credentials
that one script makes with your `gh` login: a GitHub App on the organization
(read-only: contents and metadata), and a token with `read:packages`. Run
the steps in this order. Each one prints what it does before you pipe it to
`bash`. Three of them open the browser, for a step that GitHub has no API
for:

```sh
bash driver/access/github.sh app_manifest tzvat | bash     # register the App (browser)
bash driver/access/github.sh app_convert tzvat <code> | bash  # the code from the browser's URL
bash driver/access/github.sh app_install tzvat | bash      # install it on the organization (browser)
bash driver/access/github.sh installation tzvat | bash     # its installation id
bash driver/access/github.sh packages_token tzvat | bash   # the token (browser), paste to a file
bash driver/access/github.sh check tzvat/chofesh           # verify all of it
```

The result is six files in `var/access/github/tzvat/`, not in git. Phase 25
reads them once and puts them into the cluster secret store. You can delete
the directory after the first `up`. For a public workload, skip this
section.

## 5. Up

```sh
bash driver/driver.sh local up                      # read the whole procedure first
bash driver/driver.sh local up \
  | BRZL_REPO_DEPLOY_KEY="$(<~/.ssh/brzl-local-deploy)" bash driver/kiesei.sh
```

The driver runs five phases and checks each one. Two checks print a boxed
one-time step for your machine: trust the local CA in your keychain, and,
only if you chose a host name of your own in `env/local.env`, a resolver
file. Do them when they appear. The default host name,
`brzl-local.localhost`, needs no resolver step.

## 6. See it work

- `https://brzl-local.localhost/` is the admin portal. Argo CD is at
  `/argocd/` (user `admin`, the password is in the Secret
  `argocd-initial-admin-secret`), the example app at `/apps/chofesh/`.
- Run a search on the app's page. It writes to the app's own Postgres.
- Push a change to the example app's `main`. Its CI publishes a new image.
  Within ten minutes Argo CD deploys that commit (LOCAL.md, "How a change to
  the example app arrives").

## 7. Down

```sh
bash driver/driver.sh local down | bash driver/kiesei.sh
```

The cluster goes. The registry cache, the secret store and its credentials
stay, so the next `up` is fast and needs no key.
