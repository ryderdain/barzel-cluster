# The log stack — a guide for this repo

*Draft (2026-10-19). Part of the guidebook: one file for each tool that
barzel-cluster uses. The documentation run after the last passes completes
it.*

## The three tools

**The OpenTelemetry Collector** reads logs from many places and sends them
to many places. Its configuration is a set of pipelines. Each pipeline has
receivers (where records come from), processors (what changes on the way)
and exporters (where records go). It is vendor-neutral. The `contrib` image
has the receivers and exporters this repo uses.

**OTLP** is the OpenTelemetry protocol. A record carries the log line and
two sets of attributes: those of the resource that wrote it (the pod, the
namespace) and those of the record. The collectors and the stores speak
OTLP to each other, so a store can change without a change to the
collectors.

**Loki** keeps logs. It indexes only a few labels for each stream and keeps
the lines in compressed chunks. A query first selects streams by label,
then searches their lines. So a label with many values (a pod's name) makes
Loki slow, and this repo keeps such attributes as structured metadata. They
are searchable but not indexed.

**Grafana** shows data from data sources. Each Loki store is one data
source. The query language for Loki is LogQL.

## How this repo uses them

Two stores, by purpose (ADR-0027). The admin log store keeps the records
that audit an environment. The diagnostic log store keeps the detailed
logs of the workloads and the platform applications.

```text
 the driver's machine                the cluster (namespace logs)
 ┌────────────────────────┐          ┌──────────────────────────────┐
 │ run outputs, var/run/  │          │ collector, one pod per node  │
 │ OpenBao audit log      │          │  ◀ pod logs, k3s log,        │
 │          │             │          │    API audit log, events     │
 │          ▼             │  OTLP    │          │ routes            │
 │ collector beside the   │─────────▶│          ├─▶ admin log store │
 │ cluster, queue on disk │ port 4318│          └─▶ diagnostic store│
 └────────────────────────┘          │ Grafana: a data source each  │
                                     └──────────────────────────────┘
```

The admin log store's data is outside the cluster: a host directory on
local, a bucket on a cloud. The two collectors use mutual TLS: the receiver
accepts only the client certificate that the driver issued to the
collector beside the cluster.

**Routes.** The collector in the cluster gives each record a route list:
`admin`, `diagnostic`, `cold` or `drop`. A record goes to every store in its
list. The platform's own records always go to `admin`, from the collector's
configuration. A pod's logs take the route of their namespace's
`brzl.dev/log-routes` annotation, and `diagnostic` when it has none.

**Labels.** Every record has these index labels:

| Label | Values |
| --- | --- |
| `brzl_store` | `admin-log-store`, `diagnostic-log-store` |
| `brzl_source` | `run-output`, `openbao-audit`, `k3s-server`, `api-audit`, `k8s-event`, `pod` |
| `brzl_env` | the environment, for example `local` |
| `brzl_run`, `brzl_phase` | for a run output: the run directory and the phase |
| `brzl_retention` | `7d`, `30d`, `90d` |
| `k8s_namespace_name`, `k8s_container_name` | for a pod's logs |

**Files.**

| What | Where |
| --- | --- |
| Loki, shared values and one file for each store | `gitops/infrastructure/logs/loki*.yaml` |
| The collector in the cluster | `gitops/infrastructure/logs/collector.yaml` |
| The collector beside a local cluster | `driver/substrates/k3d-otelcol.yaml` |
| The API audit policy | `driver/substrates/k3s-audit-policy.yaml` |
| Grafana's data sources | `gitops/infrastructure/monitoring/values.yaml` |

## Queries to start with

```text
{brzl_source="run-output", brzl_run="cluster-20261019T1300Z"}
{brzl_source="run-output"} |= "error"
{brzl_source="api-audit"} | json | verb="delete"
{brzl_source="openbao-audit"} | json | type="request"
{k8s_namespace_name="chofesh"}
sum by (brzl_source) (count_over_time({brzl_store="admin-log-store"}[1h]))
```

From the command line, without Grafana, through the API server:

```sh
kubectl get --raw '/api/v1/namespaces/logs/services/log-store-admin:3100/proxy/loki/api/v1/labels'
```
