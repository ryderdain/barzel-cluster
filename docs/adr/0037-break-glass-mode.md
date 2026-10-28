# ADR-0037 — Break-glass mode: hold, elevate, record, release

## Status

Accepted (designed in pass 6b, Q195–Q204, step 1 built) · **Date:**
2026-10-27 · **Extends:** ADR-0025 (the sync switch), ADR-0027 (the admin
log store), ADR-0035 (the identities) · **Amends:** ADR-0035 (the admins'
rights in Kubernetes)

## Context

In GitOps mode, Argo CD is the only writer to the cluster, and it undoes a
change to a live object. An emergency can need a change to live objects
now: a sync deployed a broken chart, Argo CD itself is broken, or a fix
cannot wait for a commit. Q62 to Q65 named the mode and its actions, `hold`
and `release`, and left the design to this pass. ADR-0035 gave every
person a verified identity, so a record can name the person. Two gaps
stood. The admins had `cluster-admin` at all times, so a hand change
outside a hold left no record of a hold. The cluster-admin kubeconfig in
the run directory skipped sign-on without a record (BACKLOG 6, 23, 29).
Grafana had no path when the cluster was down (BACKLOG 28). The working
model for an operator is `docs/BREAK-GLASS.md`.

## Decision

- **`hold` stops automated sync for the whole environment** (Q195), with
  fast mode's switch, `brzl.dev/auto-sync: "false"` on the cluster
  Secret. A second annotation, `brzl.dev/break-glass`, holds the record:
  the person, whether the name is verified, the start (UTC, ISO 8601 with
  `Z`) and the reason. Fast mode refuses while it is set. One hold per
  environment.
- **The admins are elevated only during a hold** (Q198, replaces Q194).
  Outside a hold the `brzl-admins` tier has `view`, like the other tiers.
  `hold` creates a second ClusterRoleBinding, `brzl-break-glass`, from
  `oidc:<org>:brzl-admins` to `cluster-admin`, and `release` deletes it
  (a binding's `roleRef` cannot change). Each admin acts with their own
  sign-on identity. Admins keep `role:admin` in Argo CD at all times.
- **`hold` takes the name from sign-on** (`kubectl auth whoami` with
  `kubeconfig-sign-on`) and requires membership of `brzl-admins`. `hold`
  and `release` are driver actions. Their run sheets and outputs go to the
  admin log store: the record of the start and of the end.
- **A person changes the cluster with their own `kubectl`** (Q196), not
  through the conductor. The API audit policy gets one rule: Request
  level for writes by the admins group, except Secrets. The rest stays at
  Metadata level.
- **A hold has no automatic end** (Q199). An alert, `BrzlBreakGlassHeld`,
  warns after 4 hours. An automatic release could undo an emergency fix
  in the middle of an incident.
- **`release` stops on differences from git** (Q200). It lists each
  resource that differs, with its diff. The person commits the change or
  confirms the undo (`release confirm`). Then it turns automated sync on,
  deletes the binding and the annotation, and Argo CD self-heals.
- **When Dex is down** (Q201), `hold` runs with the cluster-admin
  kubeconfig. The person gives their name with the reason, and the record
  marks the name "declared, not verified". The kiesei shell gets
  `as_admin` (the cluster-admin kubeconfig, with a banner) and `as_me`.
- **The reader of the admin log store** (Q197, BACKLOG 28) is a one-off
  driver action, usable at any time, also when the cluster is gone. It
  starts a Loki and a Grafana in containers on the operator's machine,
  on the admin store's data directory, Grafana on `127.0.0.1` with no
  sign-on. It refuses to start while the cluster's admin Loki uses the
  directory. Pass 6c adds the cold records.
- **The cluster-admin kubeconfig** stays in the run directory on local:
  the driver's credential and the Dex-down path. On a laptop it adds no
  power beyond the container engine's socket and the seal key. On a
  public cloud, pass 8 decides (BACKLOG 23). Cloud IAM gives no rights
  inside k3s. It controls the path to the API, the driver's and the
  conductor's credentials, and the emergency path.

## Consequences

- A hand change outside a hold is not possible for an admin. So every
  such change has a hold around it, with a name and a reason.
- `gitops/clusters/<env>/access/tiers.yaml` changes: admins get `view`.
  The build adds the audit rule (a local cluster needs `down` and `up`),
  the alert, the reader, and the two shell commands.
- Every Application stops syncing during a hold, and every admin is
  elevated. The hold is for the environment, not for one person or one
  Application.
- A forgotten hold only warns, and the alert has no channel yet
  (BACKLOG 21).
- In the Dex-down path the API audit log names `system:admin`. The
  declared record and the shell's history are the only link to the
  person.
- Open: an agent's path. An agent has no sign-on identity, and a run
  sheet sent to the conductor is the likely shape. Round 3 decides it.
- *Alternatives considered.* A hold for one Application only: Argo CD's
  sync windows could do it, but an emergency rarely stays in one
  Application, and one switch is simpler. Admins with `cluster-admin` at
  all times (Q194): no record separates a hold from usual work. An
  automatic end of a hold: it undoes a fix during an incident. A hold
  through the conductor: the record would name the conductor's service
  account, not the person.

## As built (pass 6b, step 1, 2026-10-27)

- `driver/modes/break-glass.sh` writes the run sheets of `hold` and
  `release`. The driver runs them at its own locus, with the cluster-admin
  kubeconfig. The emit step reads only, and its output is kept
  (`<name>-emit.out`), so a refused `hold` or `release` is on record.
- `hold` takes the person from `kubectl auth whoami` with the sign-on
  kubeconfig, with a limit of 30 s, so it never waits for a browser. Its
  record is JSON on the cluster Secret: `person`, `verified`, `start`,
  `reason`.
- `release` makes Argo CD's diff with its CLI in core mode, with the
  cluster-admin kubeconfig. That works against the v2.13 server.
- The admins' standing binding is `brzl-tier-admins-view` (`view`). The
  old `brzl-tier-admins` had `cluster-admin`, and Argo CD prunes it.
- The audit policy is a template that phase 10 writes into the run
  directory with the organization of the teams.
- kube-state-metrics gives `kube_clusterrolebinding_created`, from its
  built-in collector for ClusterRoleBindings. The alert
  `BrzlBreakGlassHeld` reads it. The first build used a custom-resource
  entry, but kube-state-metrics finds those kinds only from
  CustomResourceDefinitions. It skipped the built-in kind, and it did not
  show an error (found in the live test, 2026-10-28).
- Fast mode refuses `fast_on`, `fast_off` and `apply` during a hold.
- Phase 40 checks that the binding and the record agree, and the admins'
  rights in and outside a hold.
- Q202 (a): an agent does not hold, for now. Q203 (a): the review is a
  written rule. Q204 (a): the doctrine questions wait until after pass 6.

## As built (pass 6b, step 2, 2026-10-28)

- The reader's actions are `reader_on` and `reader_off` (Q205), with
  `driver/modes/reader.sh`. They need no cluster and no current run.
  Each writes its run sheet in a new run directory, `reader-<UTC>Z`.
- Its Loki has the store's directory read-only and runs as a querier
  alone (`target: querier`, `query_store_only`), with no ingester and no
  compactor. So it cannot change the store.
- That changes one point of the design. The decision above says the
  reader refuses while the cluster's admin Loki uses the directory,
  because two Lokis on one directory can damage it. A reader that cannot
  write removes that reason. So the reader also runs beside a running
  cluster, and it sees records up to about 15 minutes late (the cluster's
  Loki builds its index every 15 minutes). This is Q206, open with the
  user.
- Grafana shares the Loki container's network, and only Grafana's port is
  published, on `127.0.0.1` (`BRZL_READER_PORT`, 3300 on local). Its
  data source has the same name and uid as in the cluster.
- The images are the upstream ones, at the cluster's versions
  (`BRZL_READER_LOKI_IMAGE`, `BRZL_READER_GRAFANA_IMAGE`), so the reader
  does not need the registry beside the cluster. An upgrade of the
  cluster's Loki or Grafana must change them too.
- Local only: a store in a bucket needs its own settings (pass 8).
