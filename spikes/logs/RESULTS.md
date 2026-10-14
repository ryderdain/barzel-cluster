# Spike: pass-6 logs (branch `spike-logs`, never merged)

This spike checks the pass-6 log design before the build. It does not choose
products: Q97 chose the OpenTelemetry Collector, Loki and Grafana. It runs
beside the local cluster on the `brzl-local` network. The data comes from
snapshots of the run-logs, the pod logs and the k3s server log. The events and
the namespace annotations come from the live cluster API.

## Installations

| Container | Role | Data |
| --- | --- | --- |
| `brzl-spike-loki-admin` | Admin log store | Host directory `var/spike-logs/admin-store` |
| `brzl-spike-loki-diagnostic` | Diagnostic log store | Volume (lost with the cluster) |
| `brzl-spike-loki-admin-reader` | Break-glass reader | The admin store's host directory |
| `brzl-spike-otelcol` | Node collector | None |
| `brzl-spike-grafana` | Viewer, `http://127.0.0.1:3000` | None |

## Procedure

1. Start the local cluster: `bash driver/driver.sh local up | bash driver/kiesei.sh`.
2. Optional: `bash spikes/logs/spike.sh annotate | bash`. This step changes
   the cluster: it adds route annotations to the namespaces `demo` and
   `kube-system`.
3. `bash spikes/logs/spike.sh up | bash`.
4. Wait two minutes. Then run `bash spikes/logs/spike.sh check admin` and
   `bash spikes/logs/spike.sh check diagnostic`.
5. In Grafana, open Explore. Select the data source "Mixed". Add one query on
   each store, for example `{brzl_phase="25-bootstrap"}` on the admin log
   store and `{k8s_namespace_name="demo"}` on the diagnostic log store.
6. `bash spikes/logs/spike.sh kill_admin | bash`. Then
   `bash spikes/logs/spike.sh reader | bash`. Wait one minute. Then run
   `bash spikes/logs/spike.sh check reader`.
7. `bash spikes/logs/spike.sh down | bash`.

## Questions and results

| # | Question | Result |
| --- | --- | --- |
| 1 | Do all three Loki installations start with the one config? | |
| 2 | Which index labels does Loki make from the OTLP fields? Is `k8s_pod_name` only structured metadata? | |
| 3 | One run = one query: do the counts for each run and phase agree with the `wc -l` lines? | |
| 4 | Does a text search (`\|= "smoke"`) find the phase-25 lines? | |
| 5 | Routes: does `demo` go to diagnostic and cold, `kube-system` to nowhere, the run-logs to admin and cold? | |
| 6 | Do the Kubernetes events arrive (only events after the collector starts)? | |
| 7 | Does Grafana show both stores in one view? | |
| 8 | Does the reader start on the data alone? How many records does it lose against the admin check in step 4? | |
| 9 | Does the cold copy have every admin record (the gap that cold closes)? | |
| 10 | Memory of each container (`docker stats --no-stream`). | |

## Not in this spike

- The Kubernetes API audit log. It needs a new cluster with a policy file.
- The OpenBao audit log. It needs a change to the store's config file.
- Live tailing. The spike reads snapshots, so the time of each run-log line
  is the time that the collector read it.
- A short flush period for the admin Loki. If question 8 shows a large gap,
  run again with `-e LOKI_MAX_CHUNK_AGE=5m -e LOKI_CHUNK_IDLE_PERIOD=1m` on
  the admin container.

## Verdict

To write after the run.
