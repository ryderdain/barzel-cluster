# ADR-0012 — Managed NAT gateway; spot/on-demand capacity toggle

**Status:** Accepted · **Date:** 2026-06-02
**Context.** Nodes need egress (image pulls, ECR, S3); compute cost dominates the
iteration meter.
**Decision.** A single **managed NAT gateway** (prod-like); a `capacity_type`
toggle (`spot` | `on-demand`) on the compute module — spot for iteration,
on-demand `m6g.large` for the delivery demo.
**Consequences.** Prod-like egress with a documented always-on cost; cheap
iteration via spot, with a real reclaim risk (observed in eu-central-1 — the
toggle let us fall back to on-demand cleanly). NAT-instance / public-subnet are
documented cheaper levers.
