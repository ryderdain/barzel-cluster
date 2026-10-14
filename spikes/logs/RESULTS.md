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

Round 1: 2026-10-14, 16:37 to 17:07 CEST, run by the user. Default flush
settings on the admin Loki (`chunk_idle_period` 30m, `max_chunk_age` 2h).

| # | Question | Result |
| --- | --- | --- |
| 1 | Do all three Loki installations start with the one config? | Yes. But `/ready` still said "Ingester not ready: waiting for 15s" after 8 minutes, while the queries worked. Pass 6 needs a different health check, or a fix. |
| 2 | Which index labels does Loki make from the OTLP fields? Is `k8s_pod_name` only structured metadata? | Only the labels in the config, plus `service_name`, which Loki adds itself. No `k8s_pod_name` label. Yes. |
| 3 | One run = one query: do the counts for each run and phase agree with the `wc -l` lines? | They agree with the non-blank lines. The collector does not send blank lines. **Finding:** the collector also skipped 5 run-logs whose content was the same as another file's, for example four `fast-on`/`fast-off` files that hold only `secret/brzl-local-in-cluster annotated`. It identifies a file by its first bytes. They are also absent from cold. |
| 4 | Does a text search (`\|= "smoke"`) find the phase-25 lines? | Yes: 3 lines, one in each phase-25 run-log that seeds the smoke value. |
| 5 | Routes: does `demo` go to diagnostic and cold, `kube-system` to nowhere, the run-logs to admin and cold? | Yes, exactly. `demo`: 14 records in diagnostic (`brzl_retention=30d`) and 14 in `cold/30d.jsonl`. `kube-system`: none anywhere. Admin store: run-log 2222 + k3s-server 3041 + events 2 = 5265 = `cold/90d.jsonl`. No pod records in the admin store. |
| 6 | Do the Kubernetes events arrive (only events after the collector starts)? | Yes, 2 (later more: cold grew by 11 before step 6). |
| 7 | Does Grafana show both stores in one view? | Yes (the user, in Explore with "Mixed"). The labels show in the query builder. |
| 8 | Does the reader start on the data alone? How many records does it lose against the admin check in step 4? | It starts, but it found **nothing**. After 22 minutes, the admin store's directory held only `delete_requests.gz`: Loki had written no chunk and no index to storage. With the defaults, the loss window is up to 2 hours. This does not yet show that the reader can read data that was written. |
| 9 | Does the cold copy have every admin record (the gap that cold closes)? | Yes. Every admin record was in `cold/90d.jsonl` within seconds, and it was still there after the kill. |
| 10 | Memory of each container (`docker stats --no-stream`). | Not measured. |

Round 2: 2026-10-14, 17:25 to 17:57 CEST, run by the user. It answers
question 8 again with a short flush on the admin Loki (`chunk_idle_period`
1m, `max_chunk_age` 5m), and question 10. Loki also writes its index to
storage only every 15 minutes, so the kill waits 20 minutes. `check` now lists the files in the admin store and prints
the memory.

1. Remove the round-1 data by hand: `rm -rf var/spike-logs`.
2. Optional: `bash spikes/logs/spike.sh annotate | bash`.
3. `SPIKE_ADMIN_FLUSH=short bash spikes/logs/spike.sh up | bash`.
4. Wait 20 minutes. Then run `bash spikes/logs/spike.sh check admin`.
5. `bash spikes/logs/spike.sh kill_admin | bash`, then
   `bash spikes/logs/spike.sh reader | bash`. Wait one minute. Then run
   `bash spikes/logs/spike.sh check reader`.
6. `bash spikes/logs/spike.sh down | bash`.

| # | Question | Result |
| --- | --- | --- |
| 8 | Does the reader start on the data alone? How many records does it lose? | **Yes.** After 20 minutes the admin store held 69 chunk files and one index file. The reader, with no WAL, found every run-log line (2222) and every k3s-server line (3108). It lost **4 of 32 events**: the newest records, not yet in a saved chunk when the admin Loki was killed. So the loss window is the flush time: minutes, not hours. |
| 9 | Does the cold copy close that gap? | Yes. `cold/90d.jsonl` held 5362 records at the admin check (= 3108 + 32 + 2222) and 5364 later, so the 4 lost events are in it. |
| 10 | Memory of each container | Grafana 340 MiB, collector 180 MiB, admin Loki 173 MiB, diagnostic Loki 116 MiB, reader 155 MiB. About 0.8 GiB beside k3d for the full stack. |
| 1 | Readiness, again | `/ready` still said "Ingester not ready: waiting for 15s" in all three Loki installations, while every query worked. |

## Not in this spike

- The Kubernetes API audit log. It needs a new cluster with a policy file.
- The OpenBao audit log. It needs a change to the store's config file.
- Live tailing. The spike reads snapshots, so the time of each run-log line
  is the time that the collector read it.

## Verdict

The design from Q84 to Q102 works as specified, with the OpenTelemetry
Collector, two Loki installations and Grafana (Q97). Pass 6 builds it, with
these changes from the spike:

1. **The admin log store flushes early.** With Loki's defaults (30m idle, 2h
   age), a lost cluster loses up to 2 hours of admin records. With 1m idle
   and 5m age, the spike lost only the newest 4 records of 5362. The cold
   copy keeps those. The diagnostic store keeps Loki's defaults.
2. **The break-glass reader is feasible as designed:** a fresh Loki on the
   stored data alone reads it back. For the last minutes before a loss, it
   also needs the cold copy (pass 6b).
3. **Each run-log starts with a header line** (Q102). Without it, the
   collector skips a file that has the same first bytes as another.
4. **The health check is not Loki's `/ready`.** It kept reporting "not
   ready" while Loki served queries. Pass 6 finds the cause or checks a
   query instead.
5. **The memory budget is about 0.8 GiB** for the stack beside k3d, Grafana
   being the largest part.

Blank lines in run-logs are not shipped. Loki adds a `service_name` label by
itself. Neither one changes the design.
