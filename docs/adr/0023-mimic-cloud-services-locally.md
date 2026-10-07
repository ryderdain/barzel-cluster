# ADR-0023 — Mimic cloud services locally now; decide on portable services later

**Status:** Accepted · **Date:** 2026-10-07
**Context.** The local environment must test the four cloud functions that
each workload uses. These are a secret store, customer-managed encryption, a
pull-through cache, and a private push registry. Two architectures are possible.
One architecture uses local alternatives behind the same adapter interface. The
other architecture operates the same in-cluster software on each substrate.
**Decision.** Use local alternatives at this time. The k3d adapter supplies these:

- **Zot** as the pull-through and push registry. It operates external to the
  k3d cluster, and its data stays when the cluster is made again.
- **OpenBao** in dev mode, for KV and transit. **Vault Community Edition** is
  the fallback. One value in the environment definition selects it.

ESO is the read boundary. Each type of store has one write adapter. AWS keeps
Secrets Manager, KMS, and ECR. All bootstrap secret sources give their values
to the driver as environment variables. Examples are exported values, GitHub
Secrets in CI, and password-manager CLIs.
**Considered options.**

- The same software on each substrate (OpenBao and Zot or Harbor, with cloud
  KMS only to unseal and for volumes). This is a strong architecture for more
  than one cloud, because DigitalOcean has no KMS or pull-through cache that is
  equal to AWS. Make this decision when a second cloud is in use.
- LocalStack. Rejected: high cost, and it copies only some AWS functions.

**Consequences.** ESO support for OpenBao has alpha status. Thus `up` includes
a test that writes a secret and reads it back, and the versions are pinned.
The local image patch and `k3d image import` are removed. The local cluster
pulls images through Zot, as a cloud cluster pulls them through ECR.
