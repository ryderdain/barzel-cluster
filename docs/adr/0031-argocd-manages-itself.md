# ADR-0031 — Argo CD manages itself

## Status

Accepted · **Date:** 2026-10-14 (split from ADR-0013,
2026-06-03) · **Refined by:** ADR-0016, ADR-0025

## Context

ADR-0013 bundled four decisions: Argo CD as the GitOps engine
that manages itself, the app-of-apps root with its sentinel render, sync
waves with an AppProject, and the repository credential. They age at
different rates. This record carries the first and the third; ADR-0016
superseded the second; ADR-0032 carries the fourth.

## Decision

- **Argo CD is the GitOps engine on every environment.** The driver installs
  it once with Helm (phase 30-gitops), then applies the platform
  ApplicationSet, which contains an Application for Argo CD itself. From
  then on Argo CD reconciles its own chart and values from git.
- **Sync waves order the platform:** operators (CNPG, ESO) before the
  applications that need them; the secret-store app at wave 2.
- **One AppProject for each environment** (`brzl-<env>`) bounds what the
  Applications may deploy and where.

## Consequences

- A change to Argo CD's own chart is a git change like any other; while
  break-glass mode holds, it is one of the named risks (BACKLOG pass 6b).
- ADR-0025 replaced the per-environment ApplicationSet files with one
  platform ApplicationSet; this decision is unchanged by it.
