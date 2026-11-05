# ADR-0039 — Environment names and the environment definition

## Status

Accepted (BACKLOG item 38, Q239, Q240, Q245–Q248) · **Date:** 2026-11-05 ·
**Extends:** ADR-0024 (local is the first environment), ADR-0022 (the
driver), ADR-0038 (the driver grammar) · **Amends:** ADR-0024 (the name of
the first environment)

## Context

ADR-0024 made the laptop cluster the first environment of the promotion
chain and named it `local`. The name did two jobs. It named a step of the
chain (`gitops/clusters/local`, the AppProject `brzl-local`, `var/run/local`)
and it named where the cluster runs (the ApplicationSet's `localPath`, the
values files `*-local.yaml`, the TLS type `local-ca`). At the same time
`BRZL_SUBSTRATE=k3d` named a control plane, not a substrate: the alternatives
to k3d are EKS and GKE, and the alternatives to the laptop are AWS and GCP.
The user saw this in the design of item 37 (Q239, Q240). An environment is
a step of the promotion chain, as in the Terraform and Ansible idioms, and a
substrate is where a cluster runs. Pass 8 adds the second environment, so
the names are set before it.

## Decision

- **An environment is named for its step: `dev`, `test`, `stage`,
  `production`** (Q239). The first environment is `dev`. It runs on the
  local substrate. `local` is not an environment name.
- **A substrate is named for where the cluster runs: `local`, `aws`, `gcp`**
  (Q240). `BRZL_SUBSTRATE=local` selects `driver/substrates/local.sh`, the
  adapter that uses k3d. Its companion files are `local-dns.Corefile`,
  `local-otelcol.yaml` and `local-zot.json` (Q246). `k3s-audit-policy.yaml`
  keeps its name: it is k3s's.
- **`env/local.env` is `env/dev.env`**, and the driver's default for
  `BRZL_ENV` is `dev` (Q240). `kiesei.sh` reads the same file.
- **The keys of the definition** (Q248). `BRZL_READER_*` are `BRZL_AUDIT_*`,
  after the mode. The values that name the environment follow it:
  `brzl-dev` for the k3d cluster, the Docker network and the transit key,
  and `var/log-store/dev` and `var/secret-store/dev`. `BRZL_PORTAL_HOST`
  (a DNS name the operator owns, and the OAuth App's callback),
  `BRZL_PORTAL_TLS=local-ca` (a TLS type) and `BRZL_KIESEI_IMAGE=kiesei:local`
  (an image built on this machine) keep their values. The `BRZL_K3D_*` keys
  are the adapter's own.
- **`gitops/clusters/dev` is the dev environment** (Q247). It takes the
  content of `clusters/local`. The AWS-era `project.yaml` and
  `in-cluster.yaml` in it go. Git keeps them for the substrate adapters
  pass (BACKLOG 10), which rebuilds the AWS path per substrate.
- **The ApplicationSet tests the substrate where it meant the substrate.**
  The extra values files (`moreValueFilesLocal`) and `localPath` apply on
  the local substrate. The test reads the cluster Secret's label
  `brzl.dev/substrate`, not the environment. Their names stay: they
  describe the local substrate.
- **The names that derive from `$env` follow on their own**: `var/run/dev`,
  the AppProject `brzl-dev`, the containers `brzl-audit-dev-*`, the OAuth
  App material `oauth-dev-client-id` and `oauth-dev-client-secret`.

## Consequences

- A live cluster cannot be renamed in place: its cluster Secret carries
  `brzl.dev/env: local`. The path is a teardown under the old names, a move
  of `var/log-store/local`, `var/secret-store/local` and the `oauth-local-*`
  files to their `dev` names, then a bootstrap. The secret store keeps the
  deploy key through the move.
- The OAuth App on GitHub keeps the name `brzl-sign-on-local` unless the
  operator renames it there. Its callback URL does not change.
- Every document that says "the local environment" says "the dev
  environment" or "the local substrate", as it means.
- The driver tests use `BRZL_ENV=test` with a definition in a scratch copy.
  `test` is now also a step of the chain. The tests do not collide with a
  future `env/test.env`, because they run in the copy.
- *Alternatives considered.* Keep `k3d.sh` and map `local` to it: a table
  for one row. Keep the `brzl-local` values in `env/dev.env`: they would
  name a thing that no longer exists. Keep both `clusters/dev` contents:
  two AppProjects named `brzl-dev` in one directory.
