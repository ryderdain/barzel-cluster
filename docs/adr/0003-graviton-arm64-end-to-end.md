# ADR-0003 — Graviton / arm64 end-to-end

**Status:** Accepted · **Date:** 2026-06-01
**Context.** arm64 offers better price/performance and is representative of modern
substrate.
**Decision.** `m6g.large` default; arm64 enforced across AMI, k3s, all
container/Helm images, and ECR pull-through manifests.
**Consequences.** Lower cost; every image in the supply chain must be arm64 (a
constraint designed for, not patched around).
