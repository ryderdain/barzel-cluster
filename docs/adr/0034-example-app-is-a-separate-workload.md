# ADR-0034 — The example app is a separate workload (chofesh)

## Status

Accepted, built in pass 5d (2026-10-16, Q141–Q147) · **Date:**
2026-10-14 (Q115; replaces the demo-app part of ADR-0017)

## Context

The demo-app (`apps/demo-app`, a Sefaria search web app whose
logic came from `ryderdain/chofesh`) lives in this repo, and the Postgres
cluster it uses is part of the platform ApplicationSet. That ties the
platform to one workload. The objective (SPEC §1, 2026-10-14) is a platform
that any workload can consume.

## Decision

- **The example app is `chofesh`** (`ryderdain/chofesh`, since 2026-10-18
  `tzvat/chofesh`), in its own repo with its own lifecycle. It keeps its Go CLI and gains a server mode (the demo-app's
  REST API), a small web page and Postgres. The changes there are kept
  small: copy what exists here, add the parts named, preserve the CLI.
- **The platform deploys it from the chofesh repo**, as one ApplicationSet
  entry like any workload, and `apps/demo-app` leaves this repo.
- **The app owns its database.** The CNPG Postgres cluster moves into the
  app's manifests, and in pass 6c its backups. The **CNPG operator stays a
  platform capability**: its resource types apply to the whole cluster and
  one operator serves every workload.
- **Any other workload can take its place**: a workload brings its
  manifests, its secrets (through the cluster secret store, ADR-0026) and
  its database; the platform gives it capabilities, a route in the admin
  portal (ADR-0028) and log routes (ADR-0027).

## Consequences

- The bring-up check (phase 40) tests the example app as a workload, not as
  part of the platform.
- The SCM generator lists an organization's repositories through the GitHub
  API, anonymously. The limit is 60 calls per hour per address, and a
  cycle costs two, every 5 minutes. When GitHub does not answer, the whole
  ApplicationSet stops rendering until it does. Argo CD keeps what it has.
- A code change on `main` reaches local in about 5 to 10 minutes: CI builds
  (both architectures), the generator polls, Argo CD syncs. Testing before
  replacement (sync hooks, Argo Rollouts) is a later addition (Q150).
- The database credential stays CNPG's. CNPG makes it and keeps it in the
  Secret `pg-app` in the app's namespace, and the app reads it directly
  (Q147). This amends the first text, which moved it to the secret store.
  Nothing outside the cluster knows this password. A workload whose secrets
  come from outside the cluster uses the cluster secret store (ADR-0026).
- *Alternatives considered.* Keep the demo-app in this repo as a swappable
  example: still one workload the platform ships. Target the barzel app: it
  is being rethought (user), and the platform must not depend on it.

## As built (pass 5d, 2026-10-16)

- **chofesh** gained `chofesh serve` (package `internal/serve`): the
  demo-app's page and search, `/healthz`, `/readyz` and `/metrics`. It also
  gained a Dockerfile and `deploy/`. There, `base` holds the Deployment, the
  Service and the CNPG Cluster in namespace `chofesh`. `local` sets one
  instance. `aws` adds backups, metrics and the dashboard, carried over
  untested. Its page uses relative links only, so the portal strips
  `/apps/chofesh/` and rewrites nothing (Q144).
- **The platform** has one `chofesh` element in the ApplicationSet with
  its own `repo` and `revision` (the public repo over https, `main`). The
  ApplicationSet renames the two images to the environment's registry as
  before. The `postgres` and `demo-app` elements, `apps/demo-app`,
  `gitops/applications/demo-app` and `gitops/operators/postgres` (the
  GitOps base) left this repo (Q146).
- **The image is the workload's** (amendment below): its CI publishes it,
  and the cluster pulls it through the registry like any upstream image.
  Phase 20 pushes only the kiesei image. Fast mode renders the app's
  manifests from its checkout beside this repo (`BRZL_EXAMPLE_APP_SRC`).
- The example app's name is in three places that must agree, and phase 30
  checks it: `BRZL_EXAMPLE_APP_NAME`, the element, the portal's location.

## Amendment (2026-10-18, Q148–Q152): how an environment follows a workload

The first build of this pass let the driver build the app's image with a
fixed tag. So a code change never reached the cluster: the tag did not
change, and `up` skips a finished phase. The driver was a stand-in for the
workload's CI, and a stand-in must not stay in the path. Decided:

- **The workload's repo has a contract.** `main` is the development
  branch. Its CI publishes an image for every push to it, under the
  commit's first 8 hex digits and the moving tag `main`. A release is a tag
  `vX.Y.Z` on `main`, made with `make release`. That target writes the tag
  into the base manifests. CI publishes the image under that tag and
  refuses a tag the manifests do not name. The repo is public and under a
  GitHub organization (`tzvat`).
- **The environment defines what it follows**, with the label
  `brzl.dev/workload-follow` on its registration (from the environment
  definition, `BRZL_WORKLOAD_FOLLOW`). `release`, the default: Argo CD
  reads the manifests at the release tag the element names, and the image
  is the tag those manifests name. `branch` (local): an SCM generator in
  the platform ApplicationSet gives the development branch's head commit.
  Argo CD reads the manifests at that commit and the image CI published
  for it. The platform renames only the registry host of the image, never
  a tag.
- **A laptop loop without a release:** `make dev-image` in the app's repo
  builds for the machine and pushes into the registry's push namespace.
  It also points the local overlay at the build. Fast mode then applies
  the checkout.
- **The workload is private** (Q153, Q154 b: privacy first, because the
  platform models a cluster that runs proprietary software). The repository and the
  package are private. The platform reads them with two read-only
  credentials. A GitHub App on the organization (contents and metadata)
  serves Argo CD as `repo-creds` for the organization and the SCM generator
  through `appSecretName`. A classic token with only `read:packages` serves
  the registry's pull-through (the container registry accepts no
  fine-grained token). `driver/access/github.sh` makes them with the
  operator's `gh` login (Q155–Q157): one subcommand per step, and the
  browser for the three steps GitHub has no API for. The files land in
  `var/access/github/<org>/`, and phase 25 seeds them into the store once.
  A host other than GitHub gets its own script with the same layout.
- *Alternatives considered.* The driver derives a tag from the checkout and
  registers it (Q148 a). The driver then stays in the workload's path. CI
  commits the tag into the manifests (Q152 a, a'). A bot then writes to
  the app's repo, and `main` needs a pull before each push, or a
  deployment branch. Argo CD Image Updater: one more component, and it
  fights the ApplicationSet over the image field. One classic token with
  `repo` and `read:packages` for everything (Q154 a): one secret, but with
  write access to every repository the account reaches.
