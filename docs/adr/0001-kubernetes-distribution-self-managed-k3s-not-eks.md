# ADR-0001 — Kubernetes distribution: self-managed k3s, not EKS

**Status:** Accepted · **Date:** 2026-06-01
**Context.** The platform must be portable across the vendor's substrate mix (bare
metal / private / public cloud, CC-capable) and reproducible by a small team. A
managed control plane (EKS) is AWS-only and runs outside an operator-held trust
boundary.
**Decision.** Run CNCF-conformant **k3s HA (3 servers, embedded etcd)** on EC2
Graviton nodes, installed by Ansible. Disable bundled traefik (ingress is
GitOps-owned); keep flannel VXLAN as the CNI.
**Consequences.** Full control-plane portability and $0 incremental control-plane
cost; demonstrates real Kubernetes operation. We own control-plane upgrades,
patching, and etcd backup/restore (work EKS would absorb). RKE2/Talos are the
documented hardening path. Full rationale + alternatives: [§3](../ARCHITECTURE.md#3-why-k3s-not-eks).
**Consideration (revisit).** A managed control plane (EKS) is *not* permanently
excluded: the vendor's value proposition includes securing workloads on public-cloud
managed services, plausibly extending to hardening/attesting the managed
control-plane nodes — so "EKS + confidential hardening" is a legitimate future
option to re-evaluate. k3s wins *here* on time/scope and because a lightweight,
self-managed, portable distro on owned/CC substrate is itself a likely vendor
target.
