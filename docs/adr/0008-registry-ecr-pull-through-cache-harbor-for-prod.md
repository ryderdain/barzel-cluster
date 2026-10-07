# ADR-0008 — Registry: ECR + pull-through cache; Harbor for prod

**Status:** Accepted · **Date:** 2026-06-01
**Context.** Need a private registry for images and OCI Helm charts with reliable
upstream caching; want portability off AWS for prod.
**Decision.** ECR with pull-through cache now; **Harbor** documented as the
production recommendation. Upstreams cached: `registry.k8s.io` (credential-free)
plus **quay.io** (ArgoCD images) and **ghcr.io** (CloudNativePG images), each via
a Secrets Manager credential ARN — AWS requires authenticated pull-through for
quay/ghcr/Docker Hub. The node instance profile carries the create-on-pull import
permissions (`ecr:CreateRepository`, `ecr:BatchImportUpstreamImage`), scoped to
the `brzl-dev-*` cache prefixes. The pull-through **credentials must live in
Secrets Manager** — ECR's `credential_arn` cannot reference Parameter Store. The
non-secret **registry host** is published to **SSM Parameter Store**
(`/brzl-dev/ecr/registry_host`) so the bootstrap resolves it on demand (see
ADR-0013), keeping the account id out of git.
**Consequences.** Managed registry with cached upstreams now; a clean OSS
migration target for portable/prod environments. Per-upstream credential secrets
to provision (Secrets Manager, prefix `ecr-pullthroughcache/`); the
account-bearing ECR host is config in Parameter Store, not a committed value.
