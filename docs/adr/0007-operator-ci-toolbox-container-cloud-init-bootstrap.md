# ADR-0007 — Operator/CI toolbox container + cloud-init bootstrap VM

**Status:** Accepted · **Date:** 2026-06-01
**Context.** Toolchain drift across a 3-person team + CI, and SSO/SSH session
timeouts killing long-running applies/upgrades.
**Decision.** A pinned, supply-chain-verified arm64 toolbox image is the unit of
execution; delivered as a container plus a cloud-init bootstrap VM. **Packer AMI**
documented as the immutable prod path. Binaries are vendored + checksum/GPG-verified.
**Consequences.** Reproducible, drift-free, timeout-proof ops; same image runs on
a laptop, a bootstrap host, or as an ArgoCD-triggered Job. An image to build,
version, and keep current (e.g. the aws-cli signing-key expiry).
