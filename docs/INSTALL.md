# Install — the local environment, from zero

This is the shortest path from a clean machine to the platform running on
it, with its example app. It is a procedure. The reference for each part is
[`LOCAL.md`](LOCAL.md). The design is in [`ARCHITECTURE.md`](ARCHITECTURE.md).

## 1. What the machine needs

- A container engine with its `docker` CLI (Docker Desktop, Colima or an
  equivalent), started, with at least 8 GiB for its VM. The environment
  needs about 5.5 GiB of it (LOCAL.md).
- `git`, `bash` 4 or later, `jq`, `curl`.
- `gh`, the GitHub CLI, logged in to your account (`gh auth login`). The
  workload's access (section 4) uses it.
- Internet access. Images come from the upstream registries through a local
  cache, and GitHub answers the platform's reads.
- No cloud account and no credentials of a provider.

## 2. The repositories

```sh
git clone git@github.com:ryderdain/barzel-cluster.git
git clone git@github.com:tzvat/chofesh.git            # the example app
cd barzel-cluster
docker build -t kiesei:local containers/kiesei       # the toolchain image
```

The example app's checkout is for `apply` only (LOCAL.md). Argo CD reads
the pushed repository, not the checkout.

## 3. The platform's own deploy key

Argo CD reads this repository with a read-only deploy key. Make one for
your clone and register it on GitHub. A deploy key needs admin rights on
the repository, so a reader without them works from a fork:

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
bash driver/access/github.sh app_manifest tzvat | bash          # browser
bash driver/access/github.sh app_convert tzvat <code> | bash    # the code
bash driver/access/github.sh app_install tzvat | bash           # browser
bash driver/access/github.sh installation tzvat | bash
bash driver/access/github.sh packages_token tzvat | bash        # browser
bash driver/access/github.sh check tzvat/chofesh
```

The result is six files in `var/access/github/tzvat/`, not in git. Five of
them the steps write. The token you write yourself, from the clipboard, with
the command the `packages_token` step prints:

| File | Written by | Holds |
| --- | --- | --- |
| `app-id` | `app_convert` | the GitHub App's id (a number) |
| `app-slug` | `app_convert` | the App's name on GitHub |
| `app.pem` | `app_convert` | the App's private key (mode 0600) |
| `installation-id` | `installation` | the App's installation id on the organization |
| `packages-user` | `packages_token` | your GitHub login, the registry's user name |
| `packages-token` | you, with the printed command | the token, `read:packages` (0600) |

Phase 25 reads them once and puts them into the cluster secret store. You
can delete the directory after the first `up`. For a public workload, skip
this section.

## 5. Sign-on

Every environment has sign-on (ADR-0035). Before the first `up`, make the
three teams of the access tiers in the organization, and one GitHub OAuth
App for this environment. `BRZL_SIGN_ON_ORG` in `env/local.env` names the
organization. Your `gh` login needs the `admin:org` scope.

```sh
# the teams brzl-admins, brzl-operators, brzl-auditors; you in brzl-admins
bash driver/access/github.sh teams tzvat | bash
# the OAuth App: opens GitHub's form and prints what to type in
bash driver/access/github.sh oauth_app tzvat local | bash
# verify
bash driver/access/github.sh sign_on_check tzvat local
```

The OAuth App's callback URL contains the portal's host name, so make it
after you choose the host name. Read [SECURITY.md](SECURITY.md), "What
GitHub gives Dex at sign-on", before you use your own GitHub account.

## 6. Up

```sh
bash driver/driver.sh local up                      # read the procedure first
bash driver/driver.sh local up \
  | BRZL_REPO_DEPLOY_KEY="$(<~/.ssh/brzl-local-deploy)" bash driver/kiesei.sh
```

Pipe the procedure to `bash driver/kiesei.sh`, not to `bash`. The phases
need the tools of the kiesei image (`yq`, `kubectl`, `helm`, `k3d`). On a
host without them, a phase cannot be emitted, and the driver stops and says
so.

The driver runs five phases and checks each one. Phase 10 also writes a
host run sheet with the steps for your machine: trust the local CA and,
for a host name that is not under `.localhost`, a resolver entry. When the
stream ends, `driver/kiesei.sh` shows those steps and asks you once before
it runs them with `sudo` (LOCAL.md, "Steps on your machine").
`env/local.env` sets `local.barzel.sh`. To use `brzl-local.localhost`,
which needs no resolver entry, export `BRZL_PORTAL_HOST` before the first
`up` and before you make the OAuth App.

## 7. See it work

- `https://<host>/` is the admin portal: you sign in with GitHub. Argo CD
  is at `/argocd/` (press "Log in via GitHub"), Grafana at `/grafana/`, the
  example app at `/apps/chofesh/` (no sign-on).
- In Grafana, Explore, the data source "Admin log store" shows every run
  output of the driver: `{brzl_source="run-output"}`.
- Run a search on the app's page. It writes to the app's own Postgres.
- Push a change to the example app's `main`. Its CI publishes a new image.
  Within ten minutes Argo CD deploys that commit (LOCAL.md, "How a change to
  the example app arrives").

## 8. Down

```sh
bash driver/driver.sh local down | bash driver/kiesei.sh
```

The cluster goes. The registry cache, the secret store and its credentials
stay, so the next `up` is fast and needs no key.
