# ADR-0034 — The example app is a separate workload (chofesh)

## Status

Accepted (design; built in BACKLOG pass 5d) · **Date:**
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
- The database credential moves to the app's own path in the secret store.
- *Alternatives considered.* Keep the demo-app in this repo as a swappable
  example: still one workload the platform ships. Target the barzel app: it
  is being rethought (user), and the platform must not depend on it.
