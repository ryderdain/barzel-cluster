#!/usr/bin/env python3
"""Generate the brzl-demo overview Grafana dashboard as a sidecar ConfigMap.
App (demo-app) panels on the left/top, Postgres (CNPG) on the right/bottom, with
a top stat row of error/lag cues so drift is obvious at a glance."""
import json

DS = {"type": "prometheus", "uid": "${datasource}"}


def tgt(expr, legend, ref):
    return {"datasource": DS, "expr": expr, "legendFormat": legend, "refId": ref}


def ts(pid, title, x, y, w, h, targets, unit="short", desc=""):
    return {
        "id": pid, "type": "timeseries", "title": title, "description": desc,
        "datasource": DS, "gridPos": {"x": x, "y": y, "w": w, "h": h},
        "targets": targets,
        "fieldConfig": {"defaults": {
            "unit": unit, "custom": {"drawStyle": "line", "fillOpacity": 12,
            "lineWidth": 2, "showPoints": "never", "stacking": {"mode": "none"}}},
            "overrides": []},
        "options": {"legend": {"displayMode": "list", "placement": "bottom", "showLegend": True},
                    "tooltip": {"mode": "multi", "sort": "desc"}},
    }


def stat(pid, title, x, y, w, h, expr, unit, steps, desc=""):
    return {
        "id": pid, "type": "stat", "title": title, "description": desc,
        "datasource": DS, "gridPos": {"x": x, "y": y, "w": w, "h": h},
        "targets": [tgt(expr, "", "A")],
        "fieldConfig": {"defaults": {
            "unit": unit, "thresholds": {"mode": "absolute", "steps": steps},
            "color": {"mode": "thresholds"}}, "overrides": []},
        "options": {"colorMode": "background", "graphMode": "area",
                    "justifyMode": "auto", "textMode": "auto",
                    "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False}},
    }


def row(pid, title, y):
    return {"id": pid, "type": "row", "title": title, "collapsed": False,
            "gridPos": {"x": 0, "y": y, "w": 24, "h": 1}, "panels": []}


green = {"color": "green", "value": None}
panels = []
i = iter(range(1, 200))
n = lambda: next(i)

# --- top stat row: the at-a-glance error/lag cues -----------------------------
panels.append(row(n(), "At a glance — errors & lag", 0))
panels.append(stat(n(), "Searches / s", 0, 1, 6, 4,
    "sum(rate(demoapp_searches_total[5m]))", "reqps",
    [green], "App search throughput."))
panels.append(stat(n(), "Sefaria errors / s", 6, 1, 6, 4,
    'sum(rate(demoapp_sefaria_requests_total{status!="200"}[5m]))', "reqps",
    [green, {"color": "red", "value": 0.001}], "Outbound calls not returning 200 — app-side drift."))
panels.append(stat(n(), "TXN rollbacks / s", 12, 1, 6, 4,
    "sum(rate(cnpg_pg_stat_database_xact_rollback{datname=\"app\"}[5m]))", "ops",
    [green, {"color": "red", "value": 0.001}], "Postgres rolled-back transactions — DB-side errors."))
panels.append(stat(n(), "Max replication lag", 18, 1, 6, 4,
    "max(cnpg_pg_replication_lag)", "s",
    [green, {"color": "yellow", "value": 1}, {"color": "red", "value": 10}],
    "Standby replay lag behind the primary."))

# --- demo-app row -------------------------------------------------------------
panels.append(row(n(), "demo-app (Sefaria search)", 5))
panels.append(ts(n(), "HTTP requests/s by status", 0, 6, 12, 8,
    [tgt("sum by (status) (rate(demoapp_http_requests_total[5m]))", "{{status}}", "A")],
    "reqps", "Served requests; a rise in 5xx is the app-error cue."))
panels.append(ts(n(), "Outbound Sefaria calls/s by status", 12, 6, 12, 8,
    [tgt("sum by (status) (rate(demoapp_sefaria_requests_total[5m]))", "{{status}}", "A")],
    "reqps", "Upstream API calls; 'error'/non-200 = upstream drift."))
panels.append(ts(n(), "Sefaria call latency", 0, 14, 12, 8, [
    tgt("histogram_quantile(0.95, sum by (le) (rate(demoapp_sefaria_request_duration_seconds_bucket[5m])))", "p95", "A"),
    tgt("histogram_quantile(0.50, sum by (le) (rate(demoapp_sefaria_request_duration_seconds_bucket[5m])))", "p50", "B"),
], "s", "Outbound API latency — climbing p95 hints at upstream trouble."))
panels.append(ts(n(), "DB rows written/s by table", 12, 14, 12, 8,
    [tgt("sum by (table) (rate(demoapp_db_rows_written_total[5m]))", "{{table}}", "A")],
    "wps", "App-side write activity — should track searches; divergence = drift."))

# --- Postgres (CNPG) row ------------------------------------------------------
panels.append(row(n(), "Postgres (CloudNativePG)", 22))
panels.append(ts(n(), "Transactions/s (commit vs rollback)", 0, 23, 12, 8, [
    tgt('sum(rate(cnpg_pg_stat_database_xact_commit{datname="app"}[5m]))', "commit", "A"),
    tgt('sum(rate(cnpg_pg_stat_database_xact_rollback{datname="app"}[5m]))', "rollback", "B"),
], "ops", "DB transaction rate; rollbacks should stay ~0."))
panels.append(ts(n(), "Active backends by pod", 12, 23, 12, 8,
    [tgt("sum by (pod) (cnpg_backends_total)", "{{pod}}", "A")],
    "short", "Connections per instance — the demo-app pool plus replicas."))
panels.append(ts(n(), "Tuples/s (in/out)", 0, 31, 12, 8, [
    tgt('sum(rate(cnpg_pg_stat_database_tup_inserted{datname="app"}[5m]))', "inserted", "A"),
    tgt('sum(rate(cnpg_pg_stat_database_tup_fetched{datname="app"}[5m]))', "fetched", "B"),
    tgt('sum(rate(cnpg_pg_stat_database_tup_updated{datname="app"}[5m]))', "updated", "C"),
    tgt('sum(rate(cnpg_pg_stat_database_tup_deleted{datname="app"}[5m]))', "deleted", "D"),
], "short", "Row-level activity — should rise with app writes/reads."))
panels.append(ts(n(), "Cache hit ratio & DB size", 12, 31, 12, 8, [
    tgt('sum(rate(cnpg_pg_stat_database_blks_hit{datname="app"}[5m])) / clamp_min(sum(rate(cnpg_pg_stat_database_blks_hit{datname="app"}[5m])) + sum(rate(cnpg_pg_stat_database_blks_read{datname="app"}[5m])), 1)', "cache hit ratio", "A"),
], "percentunit", "Buffer cache hit ratio (1.0 = all from cache)."))

dashboard = {
    "uid": "brzl-demo-overview",
    "title": "brzl-demo — app & database overview",
    "tags": ["brzl-demo", "demo-app", "cloudnative-pg"],
    "schemaVersion": 39,
    "version": 1,
    "editable": True,
    "time": {"from": "now-30m", "to": "now"},
    "refresh": "10s",
    "timezone": "",
    "templating": {"list": [{
        "name": "datasource", "type": "datasource", "query": "prometheus",
        "label": "Data source", "current": {}, "hide": 0, "refresh": 1,
    }]},
    "panels": panels,
}

configmap = {
    "apiVersion": "v1", "kind": "ConfigMap",
    "metadata": {
        "name": "brzl-demo-overview-dashboard", "namespace": "demo",
        "labels": {"grafana_dashboard": "1", "app": "demo-app"},
    },
    "data": {"brzl-demo-overview.json": json.dumps(dashboard, indent=2)},
}

# emit as YAML by hand (avoid a pyyaml dep): only need a literal block for the JSON.
out = []
out.append("# Grafana dashboard: side-by-side demo-app + CloudNativePG overview,")
out.append("# delivered as a sidecar-discovered ConfigMap (label grafana_dashboard=1; the")
out.append("# kube-prometheus-stack Grafana sidecar watches all namespaces). Generated by")
out.append("# gitops/applications/demo-app/dashboard.gen.py from verified metric names — edit there, not here.")
out.append("apiVersion: v1")
out.append("kind: ConfigMap")
out.append("metadata:")
out.append("  name: brzl-demo-overview-dashboard")
out.append("  namespace: demo")
out.append("  labels:")
out.append('    grafana_dashboard: "1"')
out.append("    app: demo-app")
out.append("data:")
out.append("  brzl-demo-overview.json: |")
for line in configmap["data"]["brzl-demo-overview.json"].splitlines():
    out.append("    " + line)
print("\n".join(out))
