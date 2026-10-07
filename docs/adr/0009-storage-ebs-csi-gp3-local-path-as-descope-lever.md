# ADR-0009 — Storage: EBS CSI + gp3; local-path as descope lever

**Status:** Accepted · **Date:** 2026-06-01
**Context.** The stateful service needs real, failover-capable persistent volumes.
**Decision.** EBS CSI driver + gp3 default StorageClass; `local-path` only as a
documented descope lever if time/cost demands.
**Consequences.** Real PVC failover semantics; EBS volumes are a teardown
cost-leak to sweep (volumes created behind PVCs).
