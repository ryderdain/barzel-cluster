# ADR-0021 — Kiesei: one operator image, driver and conductor modes

**Status:** Accepted · **Date:** 2026-10-07 · **Supersedes:** ADR-0007 (the
cloud-init bootstrap VM and the EC2 conductor)
**Context.** The EC2 conductor was an alternative to a laptop. Its purpose was
the same toolchain for each operator. A container image gives the same
toolchain on each host that has a container engine. Thus the VM added cost
and a large IAM perimeter, but no benefit. The design must also tell which
locus operates a change that replaces the cluster.
**Decision.** The operator toolchain is one image, **kiesei** (its previous
name was "toolbox"). It operates in two modes:

- The **driver** (*kiesei nahag*) operates external to the cluster. It makes
  and removes clusters, puts phases in sequence, gets approval, and collects
  outputs.
- The **conductor** (*kiesei bakar*) operates as a pod in the cluster. It
  operates the run-logs that the driver sends to it.

Substrate phases operate on the driver. Cluster phases operate on the
conductor. **A locus must not operate a phase that removes or replaces that
locus.** This repo assembles the kiesei image. It pushes the image, with
approval, to the registry of each substrate. Each environment definition pins
the image by its digest.
**Consequences.** There is no EC2 conductor. The conductor has no permission
to write to the cloud account. It has only permissions in the cluster, plus
access to the backup bucket. Teardown and compute replacement always operate
on the driver. If a business requirement makes a VM necessary, the driver can
operate on that VM with no change. The `environments/dev/00-conductor` layer
stays in the tree, frozen with all of AWS, until the AWS adapter pass.
