# ADR-0027 — Logs: an admin log store and a diagnostic log store

## Status

Accepted (design; built in BACKLOG pass 6) · **Date:** 2026-10-14 ·
**Extends:** ADR-0022, ADR-0023, ADR-0026 · **Supersedes in part:** ADR-0017
(the metrics stack is unchanged; the log design is new)

## Context

SPEC §3 promised "audited activity (run-logs + Loki)" and
"Loki + Alloy" on every substrate, but no design existed. Logs have two
concerns with different readers. **Workload logs** serve the people who
develop a workload. **Platform logs** serve operators and auditors: the
run-log outputs, the control plane, the access records and, later, the break-glass
records. An audit record that is stored in the cluster it audits is lost
with that cluster. A spike (branch `spike-logs`, `spikes/logs/RESULTS.md`)
tested the design in two rounds before the build.

## Decision

- **Two stores, named by purpose.** The **admin log store** keeps the
  bootstrap, control-plane and access records of an environment. Its data is
  outside the cluster and outlives it. The program that serves the data may
  run in the cluster (Q96a). The **diagnostic log store** keeps the detailed
  logs of workloads and platform applications. It is lost with the cluster
  unless its logs also go to another store.
- **Products: the OpenTelemetry Collector, two Loki installations, Grafana**
  (Q97). The two Loki installations are separate (Q99), so a noisy workload
  cannot slow the admin path. Each installation shows its name in its
  container, its Grafana data source, its collector exporter and a
  `brzl_store` label on every record.
- **Records travel as OTLP** (Q87), so the collector output and the store
  are separate choices for each substrate.
- **The admin log store's data is in object storage.** On local, a host
  directory mounted into the k3d node stands in for the bucket (Q104). The
  admin Loki flushes early: 1 minute idle, 5 minutes maximum age. With
  Loki's defaults (30 minutes, 2 hours), a lost cluster loses up to 2 hours
  of admin records; with the early flush, the spike lost the newest 4 of
  5362.
- **One node collector, owned by the platform, with one output for each
  destination** (Q86). A collector beside the cluster reads the run-log
  outputs from `var/run/` (Q106, local only for now).
- **The admin log store gets six sources** (Q90): the run-log outputs of
  the driver and the conductor, the k3s server log, the Kubernetes API
  audit log (metadata level), the OpenBao audit log, the Kubernetes events,
  and later the break-glass records. These routes are fixed in the
  collector's configuration, not in an annotation, so a workload cannot
  remove them.
- **Each namespace chooses where its detailed logs go**, with the annotation
  `brzl.dev/log-routes`: a comma-separated list of `drop`, `admin`,
  `diagnostic` and `cold` (Q91, Q95). A record goes to every store it names,
  at the same time. No annotation means `diagnostic`. `drop` is valid only
  alone.
- **Aging is each store's own policy.** Each store has a default retention
  period. A namespace can choose a retention class with
  `brzl.dev/log-retention: 7d|30d|90d` (Q98). The collector copies the class
  onto each record as the label `brzl_retention`, and Loki has one retention
  rule for each class. A record that must outlive its store is also written
  to `cold` when it arrives (BACKLOG pass 6c).
- **Time is UTC, ISO 8601 with `Z`, everywhere** (Q100): log lines, run
  directories (`cluster-<UTC>Z`, `teardown-<UTC>Z`, Q101) and fast-mode
  run-logs.
- **Each run-log output starts with a header line** in logfmt (Q102), for
  example
  `# brzl run-log env=local run=cluster-20261014T1425Z phase=25-bootstrap
  start=2026-10-14T14:25:18Z`. The collector identifies a file by its first
  bytes, and in the spike it skipped five one-line outputs that had the
  same content as another file.
- **Grafana in the cluster is the viewer**, with one data source for each
  store (Q94). A break-glass reader, outside the cluster, reads the admin
  data when the cluster is down (BACKLOG pass 6b).

## Consequences

- The audit trail outlives the cluster. The loss window is the admin flush
  time, and the cold copy closes it.
- The local stack costs about 0.8 GiB of memory beside k3d (spike round 2).
- Loki's `/ready` reported "not ready" while it served queries. The health
  check queries the store instead.
- Changes to how the cluster is made (the host directory mount, the API
  audit policy) need one `down` and `up`.
- Open for pass 8: the admin log store on AWS (Q96: the same product, data
  in S3; CloudWatch at most a backup copy; its OpenTelemetry exporter is
  alpha), and how the driver's run-log outputs reach it from outside local (Q106).
- *Alternatives considered.* Alloy as the collector: its OTLP file reader is
  a preview, it has no OTLP events receiver and no CloudWatch exporter.
  VictoriaLogs as a store: one retention period and local disk only. One
  Loki with two tenants: one process and one storage location for both
  stores. CloudWatch as the admin store: its query language differs from
  local's, so local would not test it.

## Amendment (pass 6 design, Q158–Q162, 2026-10-19)

- **One Grafana, from kube-prometheus-stack, on every substrate** (Q158).
  The metrics stack was AWS-only because its values held the AWS storage
  class and the ECR prefixes, not because of memory. It moves to every
  substrate, with values for each substrate. Its Grafana is the viewer, and
  the two log stores are data sources in it. The full local environment
  then needs about 5.5 GiB. A low-memory mode for smaller machines is a
  BACKLOG item, built only when a need appears.
- **Helm charts for Loki and the collector** (Q160): the `loki` chart in
  single-binary mode, once for each store, and the
  `opentelemetry-collector` chart. This is the pattern of the other
  platform applications. The spike's settings go into the values files.
- **The collector beside the cluster sends to the collector in the
  cluster** (Q162), over OTLP. It keeps a queue on disk in
  `var/log-store/<env>/queue/`. The run outputs written while the cluster
  is absent (phases 10 to 30, a `down`) arrive when it is back. The route to the
  admin log store stays in one configuration, the in-cluster collector's.
  Q106 and Q96a stand as decided: the collector beside the cluster on
  local, the admin Loki in the cluster with its data outside.
- `driver.sh <env> state` left this pass (Q161). It is a BACKLOG item of
  its own: a read-only list of the state kept outside the cluster.

### As built (pass 6, 2026-10-19)

- **No port mapping.** The collector chart opens host ports 4317 and 4318
  on each node. The collector beside a local cluster reaches the server
  node by its container name on the shared network. So Q162 needs no k3d
  port mapping. The cluster is made again only for the audit policy, the
  k3s log file and the admin data's mount.
- **Loki's readiness.** The chart's configuration (a memberlist ring)
  reports ready after about 45 seconds. The spike's "not ready" came from
  its in-memory ring. The chart's readiness probe stays. The check of
  phase 40 still asks each store with a query.
- **The Grafana password** is in the cluster secret store, and ESO
  projects it (Q105, as decided). On AWS, the bootstrap makes it until the
  AWS store exists (pass 8).
- **The ApplicationSet** gained element keys for this: more values files,
  values files for local only, a registry prefix in front of an image
  path, the portal's host name and the environment's name. The prod copy
  of the monitoring values went, because the prefixes come from the
  cluster Secret now.
- **Memory, measured** (2026-10-21): the full local environment used
  5.0 GiB, the k3d node 4.7 GiB of it. The estimate was 5.5 GiB.
- **The OpenBao audit device is in the store's configuration** (OpenBao
  2.3 and later), not made through the API.

### Open after pass 6

- The in-cluster collector accepted OTLP from any pod and from any
  container on the local network, without a credential. Something other
  than the platform could write records that look like the admin path's.
  Closed on local by BACKLOG 4a (below).
- The events come from a receiver in each collector pod. With more than
  one node, each event arrives once from each node. Each copy names the
  node of its collector (`brzl.collector.node`, structured metadata), so
  a reader can tell the copies apart and keep one. Pass 8 moves the
  events to one replica.
- Every platform record names the node of the collector that read it,
  added 2026-10-21. With more than one server, it tells which server's
  k3s log or API audit log a line came from.
- Open on AWS (pass 8): the admin log store's data in S3, and the k3s
  audit policy and log file through Ansible. Grafana needs the portal's
  host name and its password from the AWS store.

## Amendment (BACKLOG 4a, Q163–Q166, 2026-10-22): the OTLP receiver

- **Mutual TLS from the store's CA** (Q163). The receiver presents a
  server certificate and accepts only a client certificate from the
  store's CA. The CA was already there (ADR-0036). mTLS also encrypts the
  traffic, and it leaves no shared secret that someone could copy and
  replay.
- **The receiver's certificate comes from cert-manager** (Q164), through
  the portal's issuer, as `log-intake.<portal host>`. It renews on its
  own, on every substrate. The portal's PKI role already allowed names
  under the host, so no store policy changed and no purge was needed.
- **The client certificate comes from the driver** (Q164). Its holder,
  the collector beside the cluster, runs outside the cluster, where
  cert-manager does not write. The PKI role `log-shipper` signs client
  certificates for that one name, and no auth role names it. Phase 10
  issues the certificate on every run, valid for 30 days. The store's CA
  moved from phase 25 to phase 10 for this, so it exists before the
  collector starts. A local cluster that lives longer than 30 days queues
  its run outputs until phase 10 runs again.
- **The portal role signs server certificates only.** The receiver trusts
  any client certificate from the CA, so only the client-only role may
  make one. A test showed that a server-only certificate from the same CA
  is refused as a client.
- **Only HTTP on the node's host port is open** (Q165). gRPC is closed.
  The chart makes no Service for a DaemonSet.
- **Workloads never send OTLP to the platform's collector** (Q166). What
  arrives over OTLP is the platform's own records, so the admin route on
  that intake stays correct. A workload that wants OTLP gets its own
  collector or a later design.
- **On a cloud (pass 8)**, the choice is a private CA or a public CA for
  these certificates (the user, 2026-10-22). A token only if it brings a
  clear gain.

## Amendment (pass 6c, Q210–Q217, 2026-10-28): the cold log store on local

- **On local, the cold log store is a host directory** (Q210),
  `var/log-store/<env>/cold/`, mounted into every k3d node at
  `/var/lib/brzl/cold-log-store` (Q214). The alternative was an
  S3-compatible store beside the cluster (the Versity S3 Gateway). That is
  about as much work as pass 6b, and a laptop does not need database
  backups. So the S3 store moves to the remote staging environment, with
  the backups (BACKLOG item 9).
- **The collector writes the cold records as JSON lines** (Q215), with its
  file exporter: OTLP JSON, one line for each batch, no compression. The
  path is `<node>/platform/<source>.jsonl` or
  `<node>/namespaces/<namespace>.jsonl`. Each node has its own directory,
  so two collectors never write to the same file. At 100 MB, a file gets
  the UTC time in its name, and a new file starts. With rotation set, a
  restarted collector appends to its files. Without rotation, the exporter
  empties a file when it starts.
- **Nothing removes cold records on local** (Q212), also not `down`.
  `max_backups: 0` keeps every old file. A cloud uses a lifecycle rule on
  its bucket (pass 8).
- **`jq` reads the cold records** (Q216). The reader stays for the admin
  log store. RECOVERY.md has the command.
- The cold copy is on the host's disk within seconds. So on local it
  closes the admin store's loss window, as the Consequences above expect.
- The settings are in `collector-local.yaml`, for local only. On a cloud,
  `cold` has no destination until pass 8.
- Phase 40 checks that each admin source has a cold file that is not
  empty.
- Moved out of this pass (Q217): the database backups (CNPG with the
  Barman Cloud Plugin, Q211) and a restore drill (Q213) go to the remote
  staging environment (BACKLOG item 9). chofesh's AWS overlay uses the
  in-tree `barmanObjectStore`, which CNPG 1.29 deprecates. It moves to the
  plugin in pass 8, before CNPG 1.31 removes the in-tree support.
