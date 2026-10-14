# ADR-0033 — Metrics: kube-prometheus-stack, trimmed

**Status:** Accepted (AWS substrate) · **Date:** 2026-10-14 (split from
ADR-0017, 2026-06-04)

**Context.** ADR-0017 bundled the metrics stack, access to its UIs by
port-forward, and the demo-app's rebuild as a Sefaria search app. ADR-0028
supersedes the access part and ADR-0034 carries the demo-app. This record
carries the metrics stack as decided.

**Decision.**

- **kube-prometheus-stack** (Prometheus, Grafana, node and kube-state
  exporters) is the metrics stack, installed by the platform ApplicationSet
  as the `monitoring` app. Alertmanager is off until a receiver exists;
  the PVC sizes are trimmed; workloads expose metrics through a
  PodMonitor or ServiceMonitor.
- **Today it is an AWS-only app** in the ApplicationSet (ADR-0025). Pass 6
  brings Grafana to every environment as the log viewer (ADR-0027); the
  metrics stack on local is then decided with it, so that each environment
  has one Grafana.

**Consequences.**

- Metrics and logs are separate concerns with separate collectors (Q78);
  Grafana is the one viewer for both.
- Open: the metrics stack on local, and Alertmanager's receiver.
