# ADR-0032 — Argo CD's repository credential: deploy key now, GitHub App next

## Status

Accepted; to be superseded in pass 8 · **Date:** 2026-10-14
(split from ADR-0013, 2026-06-03; the gate decided 2026-10-12, Q61)

## Context

The repository is private since 2026-10-12. Argo CD must read
it on every environment. ADR-0013 gave it a read-only deploy key. A deploy
key is one key for one repo, with no expiry and no audit of its use; it is
acceptable for a laptop environment and not beyond.

## Decision

- **Local uses the read-only deploy key `sleipnir-brzl-deploy`.** The driver
  reads it once from the bootstrap secret source `BRZL_REPO_DEPLOY_KEY`,
  seeds it into the cluster secret store, and writes Argo CD's repository
  Secret from the store (ADR-0026). The key is given once.
- **Before any environment beyond local**, the credential becomes a
  **GitHub App** installation: short-lived tokens, one installation for each
  environment, revocable and audited. This is a gate on BACKLOG passes 7h
  and 8, on every environment at once.

## Consequences

- Until the gate, no environment other than local may follow the repo.
- The GitHub App needs its own bootstrap secret source (the app's private
  key) and a secret-store path for each environment.
