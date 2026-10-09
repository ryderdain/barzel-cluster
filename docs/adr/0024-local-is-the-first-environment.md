# ADR-0024 — Local is the first environment in the promotion chain

**Status:** Accepted · **Date:** 2026-10-07 · **Supersedes:** ADR-0015
**Context.** ADR-0015 made the local k3d cluster a laptop exception that is
not in the promotion chain. It used `kubectl apply -k` and its own overlay,
with no Argo CD, and `platform.sh` refused it. At this time, the local
environment must be a fast test harness for changes to the cluster
structure. It must also be sufficiently near to the cloud model to test
workloads. The barzel container
is the first workload. The demo-app is the smoke workload.
**Decision.** The promotion chain is local, then dev, then prod. The local
environment has its own environment definition, and the same driver operates
it. It has two modes:

- **GitOps mode** is the default. Argo CD makes the cluster agree with a
  pushed git branch.
- **Fast mode** is for changes to the cluster structure. `fast_on` stops the
  Argo CD auto-sync, and the driver applies the working tree directly.
  `fast_off` starts the auto-sync again, and Argo CD makes the cluster agree
  with the branch.

The local cluster is disposable: each `up` starts from zero. k3s stays the
Kubernetes distribution on each substrate.
**Consequences.** Each substrate gets Argo CD. Thus a good local run also
tests the delivery path. The k3d substrate adapter replaces `k3d-up.sh` and
the local overlay. You cannot test changes to cloud Terraform locally. You can
test the platform layer above Kubernetes, and that layer is the same on each
substrate.
