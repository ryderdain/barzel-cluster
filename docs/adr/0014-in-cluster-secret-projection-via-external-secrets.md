# ADR-0014 — In-cluster secret projection via External Secrets Operator

**Status:** Accepted · **Date:** 2026-06-04
**Context.** The demo app runs in its own `demo` namespace (team-style separation
from the operator), but its database credential is the CNPG-generated `pg-app`
secret in `cnpg-demo`. Kubernetes Secrets don't cross namespaces, and we won't
copy a credential into git or grant the app broad read access to the operator's
namespace. We also want one coherent, declarative answer to "how are secrets
distributed" for the security story.
**Decision.** **External Secrets Operator** (wave-1 operator, GitOps-installed)
projects the credential. A **least-privilege reader ServiceAccount** in
`cnpg-demo` may `get`/`list`/`watch` only the single `pg-app` secret; a
cluster-scoped **`ClusterSecretStore`** (Kubernetes provider, `remoteNamespace:
cnpg-demo`) authenticates as that SA; an **`ExternalSecret`** in `demo`
materialises `demo/pg-app`. The DSN is **rebuilt via ESO templating** with the
`pg-rw.cnpg-demo.svc.cluster.local` FQDN (CNPG's own `uri` embeds the short
`pg-rw` host, which wouldn't resolve from `demo`) and `sslmode=require`. ESO
images route through ECR pull-through (ghcr upstream, `brzl-dev-github` prefix,
ADR-0008); CRDs are `external-secrets.io/v1beta1` (chart 0.10.7). ESO is
deliberately the same operator that would consume **AWS Secrets Manager** (already
the store for the ECR pull-through credentials, ADR-0008/§secret store), so one
tool spans in-cluster and external secret sources.
**Consequences.** The app keeps its own namespace while **CNPG still owns and
rotates** the credential — ESO's refresh interval picks up rotation. The credential
never lands in git and the app never reaches into `cnpg-demo`. Costs: one more
operator + CRDs to run/upgrade, and a `ClusterSecretStore` + scoped RBAC to
maintain. Prod extension: point ESO at the **AWS Secrets Manager provider** (with
an IRSA-scoped SA) for externally-sourced application secrets.
