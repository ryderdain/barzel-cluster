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

- **The example app is `ryderdain/chofesh`**, in its own repo with its own
  lifecycle. It keeps its Go CLI and gains a server mode (the demo-app's
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
- **The image, for now:** phase 20 builds it from the app's checkout
  beside this repo (`BRZL_EXAMPLE_APP_SRC`, `../chofesh`). It pushes it to
  the local registry, as it did for the demo-app. Fast mode renders the
  app's manifests from that checkout too. The app publishes its own image
  from its own CI in pass 8 (Q141).
- The example app's name is in three places that must agree, and phase 30
  checks it: `BRZL_EXAMPLE_APP_NAME`, the element, the portal's location.
