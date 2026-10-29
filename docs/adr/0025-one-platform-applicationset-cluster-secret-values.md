# ADR-0025 — One platform ApplicationSet; values and sync switch per cluster

## Status

Accepted · **Date:** 2026-10-12 · **Extends:** ADR-0016, ADR-0024

## Context

ADR-0024 puts Argo CD on every environment, local included. Dev
and prod each had an ApplicationSet file. The two files were the same except
for the values per environment: the pull-through prefixes, the demo-app image,
the AppProject, the prod values file for monitoring, and the prod NodePort. A
third copy for local would make three files to keep the same. Fast mode
(local) and break-glass mode (any environment, BACKLOG pass 6b) must stop
automated sync. The ApplicationSet owns its Applications, so a change made
directly to an Application is reverted. ADR-0016 records a further danger: a
renamed element makes the ApplicationSet delete the old Application, and the
finalizer of that Application then deletes what it deployed. The Argo CD
configuration of dev was lost that way once.

## Decision

- **One ApplicationSet**, `gitops/platform/applicationset.yaml`, for every
  environment. It keeps every Application name, wave and AWS value of the
  dev and prod files. An offline render with the ApplicationSet template
  engine (Go `text/template` + sprig) showed the same 7 Applications for dev
  and for prod, field for field.
- **The cluster Secret holds all per-environment values**, as ADR-0016 began:
  - labels `brzl.dev/env` (the AppProject and the prod changes) and
    `brzl.dev/substrate` (the AWS-only apps, from a second matrix).
  - annotations `brzl.dev/registry-host`, `brzl.dev/prefix-<upstream>`,
    `brzl.dev/demo-app-image`, `brzl.dev/demo-app-tag`,
    `brzl.dev/backup-bucket` and `brzl.dev/revision`.

  On AWS the bootstrap writes them. On local, phase 30-gitops writes them
  from the substrate adapter: Zot is the registry host, and each upstream's
  Zot namespace is its prefix. Thus local pulls through the same
  `host/prefix/path` shape as the cloud.
- **The sync switch is the annotation `brzl.dev/auto-sync`.** With the value
  `"false"`, the ApplicationSet renders each Application without automated
  sync. No commit is necessary, and nothing reverts the switch. `fast_on`,
  `fast_off` and, later, break-glass `hold` and `release` change only this
  annotation. Phase 30-gitops never writes it, so a run of that phase again
  keeps the mode.
- **A guard against the ADR-0016 cascade, in place of a golden render
  test:**
  - `syncPolicy.applicationsSync: create-update`: the ApplicationSet never
    deletes an Application.
  - `syncPolicy.preserveResourcesOnDeletion: true`: a deleted Application
    does not delete what it deployed.
  - phase 30-gitops stops with `error 3` before it applies an ApplicationSet
    that leaves a live Application without an element.

  The Argo CD values set `applicationsetcontroller.enable.policy.override`, so
  that the per-ApplicationSet policy has an effect.
- **Fast mode applies the working tree with Argo CD's own injection.** `apply`
  reads the images and patches from each live kustomize Application. It puts
  them over the working-tree path, and the conductor applies the result. The
  template logic is not copied. Helm apps change only through a pushed branch.

## Consequences

- One file to change for all environments. A per-environment difference
  becomes a label or an annotation, not a copy of the file.
- A renamed or removed element leaves the old Application in place. An
  operator removes it on purpose, in this order (found in pass 5d): drop the
  element from the ApplicationSet in the cluster (a JSON patch), delete the
  Application, delete its namespace, then run phase 30 again. The order
  matters. While the element is in the live ApplicationSet, a deleted
  Application comes back at once. The guard stops phase 30 as long as the
  Application exists. The check of phase 30 passes only when the
  ApplicationSet in the cluster has the file's elements. So a run that
  stopped at the guard does not earn an `.ok`.
- When a fast-mode change is not pushed before `fast_off`, Argo CD removes it.
  This is intentional: the branch is the truth.
- The AWS bootstrap (`gitops/bootstrap/bootstrap-argocd.sh`) writes the new
  annotations, but nobody can test it before pass 8.
- *Alternatives considered:* one ApplicationSet per environment, with dev and
  prod frozen. It is less work now, but there are three copies. A golden
  render test on a disposable cluster: it adds manual steps for one purpose
  and does not work on dev or prod. Patching each Application and
  `ignoreApplicationDifferences`: it is more parts, and they fight the
  controller.

## Amendment (2026-10-18, pass 5d, ADR-0034)

The annotations `brzl.dev/demo-app-image` and `brzl.dev/demo-app-tag` are
gone. A workload's image is the workload's own, published by its CI; the
platform renames only the registry host. The label
`brzl.dev/workload-follow` (`branch` or `release`) is the per-environment
value for workloads, written by the bootstrap or phase 30 like the others.
The workload's element sits in a nested matrix with an SCM generator.

## Amendment (2026-10-22, Q167 and Q168, BACKLOG 20)

- **A failed sync is retried with no limit** (`retry.limit: -1`): after
  10 s, then twice as long each time, at most every 3 minutes. The limit
  of 5 stopped a sync for good after a passing DNS fault. Argo CD does not
  try the same commit again by itself, so an operator had to refresh and
  sync by hand. A real fault now keeps retrying, and its error stays on
  the Application.
- **Phase 40 names an Application that fails 3 times or more**, with its
  error, while it waits. It stays read-only.
- **An alert, `BrzlSyncFailing`**: a warning at 3 failed attempts and a
  critical alert at 5, from kube-state-metrics, which reads each
  Application's retry count. It counts only an Application that is not
  Synced. The count and the phase of the last operation stay on the
  Application after its resources converge. The alert shows in
  Grafana and Prometheus. No channel sends it yet (BACKLOG 21).

## Amendment (2026-10-29, item 13): the sync switch

- **"Fast mode" is gone. The switch has the name of what it does** (the
  user, 2026-10-29; GLOSSARY "Sync switch"). The driver's verbs are `sync
  off`, `sync on [confirm]` and `apply`, on local only
  (`BRZL_SYNC_SWITCH_ALLOWED`). Break-glass `hold` and `release` move the
  same switch, with a record and the elevation (ADR-0037).
- **`apply` is Argo CD's own local sync** (Q224): `argocd app diff --local`
  at emit time, then `argocd app sync --local` for each kustomize
  Application that differs, in core mode. Argo CD renders the working
  tree with the Application's images and patches and writes its own
  tracking marks. So the copy of its injection in `fast-mode.sh` is gone.
  This needs one `source:` on each kustomize Application, not a list:
  the CLI refuses `--local` on a list, also a list of one.
- **`sync on` has `release`'s check** (Q225): it stops while an
  Application differs from git and shows the diff. Commit and push, or
  `sync on confirm`. One function, `differences_from_git`, serves both.
- **`apply` with sync on shows the diff and stops** (Q226). Argo CD refuses
  a local sync while automated sync is on, and self-heal would undo it.
- **The tracking method is Argo CD's default** (annotation, v3; Q227).
  Nothing of ours writes tracking marks any more.
- The Decision's bullet "Fast mode applies the working tree with Argo
  CD's own injection" and the Consequence on `fast_off` are replaced by
  this amendment.
