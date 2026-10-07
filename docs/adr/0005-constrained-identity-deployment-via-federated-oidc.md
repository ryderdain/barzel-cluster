# ADR-0005 — Constrained-identity deployment via federated OIDC

**Status:** Accepted · **Date:** 2026-06-01
**Context.** Long-lived static credentials are the most common cloud-breach
vector and don't scale to a team + CI.
**Decision.** Admin performs only the one-time trust-anchor bootstrap; all
subsequent runs assume scoped least-privilege roles via OIDC (humans via IAM
Identity Center; CI via `AssumeRoleWithWebIdentity`). Native AWS OIDC now; **Ory**
documented as the portable prod IdP.
**Consequences.** No static deploy creds; auditable, least-privilege automation.
Adds an identity trust-anchor layer to bootstrap and maintain.
