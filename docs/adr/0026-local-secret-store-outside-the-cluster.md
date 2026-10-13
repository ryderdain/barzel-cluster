# ADR-0026 — The local cluster secret store runs outside the cluster

**Status:** Accepted · **Date:** 2026-10-13 · **Extends:** ADR-0023

**Context.** ADR-0023 chose OpenBao as the local stand-in for the cloud secret
store. The first plan put it in the cluster, as an Argo CD Application. That
plan failed the parity test before it was built. AWS Secrets Manager exists
before the cluster and outlives it. The cluster reaches it over the network,
and the operator writes to it with their own credential. An in-cluster OpenBao
breaks this in three ways. It comes after Argo CD. It loses its data at each
`down`. And the operator must give each bootstrap secret again at each `up`.
Phase 25 showed the symptom: the deploy key was necessary at every run. Zot
already follows the cloud model locally.

**Decision.**

- **OpenBao runs beside the cluster, like Zot.** It is one container on the
  environment's container network, with its own volume. The substrate phase
  makes it before the cluster, because k3d writes the network's members into
  CoreDNS when it makes the cluster. `down` keeps it. The driver reaches it at
  `127.0.0.1:8200`, and the cluster at `brzl-openbao:8200`.
- **Persistent storage, not dev mode.** The store uses `pebbledb` storage on
  the volume, and the built-in static seal. The 32-byte seal key is a file on
  the driver side: `var/secret-store/local/seal.key`, gitignored, mode 600.
  The phase makes it once and passes it to the container through the
  container's environment. It is the local equivalent of KMS, which holds the
  key on AWS. A lost key is a lost store. Then the operator purges the store
  and starts again.
- **Init once, root revoked.** On the first start, the phase initializes the
  store. It writes the `driver` and `eso-reader` policies, enables KV v2 at
  `secret/`, enables transit with one key, and enables Kubernetes auth. It
  mints the `driver` token into `var/secret-store/local/driver.token`, and it
  revokes the root token. The recovery key stays beside the token, to mint a
  new root token if the driver token is lost. Self-initialization was
  considered and not used. It cannot hand a token back, and 2.7.1 has an open
  parser defect in it.
- **The driver seeds the store, and the store bootstraps the cluster.** Phase
  25 writes each bootstrap secret source that is set with the adapter's
  `secret_put`. Today that is the deploy key. Then the phase reads the deploy
  key back from the store into Argo CD's repository Secret. So a secret enters
  once, from the operator, and the store keeps it.
- **ESO reads through the Vault provider, with Kubernetes auth.** OpenBao is
  outside the cluster, so it verifies ESO's service-account token against the
  cluster API. For that it has a reviewer service account with the
  `system:auth-delegator` role, and a long-lived token that the phase gives
  it. Workloads use one store name, `brzl-secrets`. Each environment defines
  that store in its own `gitops/clusters/<env>/secret-store` path, and the
  platform ApplicationSet deploys that path as the `secret-store` app. The
  native `openBao` provider is alpha and read-only. The Vault provider is
  stable and has PushSecret.
- **The smoke test lives in the phases that already run.** Phase 25 writes a
  random value through the store and keeps its hash. The check of phase 40
  compares that hash with the Secret that ESO projected. No value is compared
  or printed.
- **One adapter per store type**, with these functions: `secret_store_up`,
  `secret_store_prelude`, `secret_store_bind_cluster`, `secret_put <path>
  <VAR>`, `secret_get <path>`, `secret_exists <path>`, `secret_store_check`
  and `secret_store_has <path>`. Values travel on stdin, and the token travels
  through the environment. A run-log names only variables.

**Consequences.**

- Local now has the cloud's shape. The store is external and persistent, and
  the driver and the cluster reach it alike. The deploy key is given once.
- Three driver-side files hold the trust: the seal key, the driver token and
  the recovery key. They are the operator's credential, as an AWS profile is
  on AWS. `docs/SECRETS.md` lists them.
- A change to the store's config replaces the container. The volume and the
  seal key stay, so the store unseals again. k3d does not update CoreDNS when
  the address of a network member changes. So a replaced store must keep its
  address, or the cluster needs `down` and `up`.
- AWS (pass 8) implements the same adapter with Secrets Manager, and its own
  `secret-store` path. Dev and prod need those paths before their
  `secret-store` Application can sync (BACKLOG).
- *Alternatives considered.* OpenBao in the cluster: not a mimic (order, data
  loss, re-entry of secrets). Dev mode: in-memory, the same loss. Shamir
  unseal by the driver: more steps, the same trust. A static token for ESO: a
  secret to distribute, where Kubernetes auth mimics IRSA.
