# ADR-0013 — GitOps: ArgoCD app-of-apps with sync waves; self-managed

**Status:** Accepted · **Date:** 2026-06-03
**Context.** The cluster config must be declarative, ordered (operators before the
apps that depend on them), and reproducible by the team — not a pile of imperative
`kubectl apply`s. ArgoCD itself needs to be installed before it can manage
anything, and it must read a **private** repo whose image refs point at an
**account-bearing** ECR host.
**Decision.** **ArgoCD** drives the cluster via an **app-of-apps**: one hand-applied
root Application (`gitops/clusters/dev/root.yaml`) watches a flat dir of child
Applications, each tagged with `argocd.argoproj.io/sync-wave` so they reconcile in
order — ArgoCD self-management (wave -1), EBS CSI + gp3 default SC (wave 0), then
operators (CNPG) and applications in later waves. All apps are scoped to an
`brzl-dev` **AppProject**. ArgoCD is **bootstrapped once via Helm**
(`gitops/bootstrap/bootstrap_argocd.sh`, an emit-commands script) and then
**re-adopts its own release** through the wave-(-1) Application, so future ArgoCD
upgrades are git changes. Private-repo reads use a **read-only GitHub deploy key**
held in a gitignored Secret (`.example` committed). Helm charts are fetched from
their upstream repos; only the **container images** are routed through ECR
pull-through (ADR-0008) via committed values.
**Account-id hygiene.** Committed Helm values use a `__ECR_REGISTRY_HOST__`
sentinel rather than the real `<account>.dkr.ecr…` host, so no account id lands in
the delivered repo (consistent with the tfvars/backend hygiene rule). The real
host is published by 40-ecr to **SSM Parameter Store**
(`/brzl-dev/ecr/registry_host`); the bootstrap reads it from there (STS fallback)
and resolves the sentinel via `helm --set` for the one-time install. For the
self-managed Applications it is resolved in git (PoC) — the clean prod resolutions
are an **ApplicationSet cluster generator** (host as a cluster-Secret value, never
in git) or **Harbor**, whose stable hostname carries no account id (reinforcing
ADR-0008's Harbor-for-prod story). *(A brief detour to keep all of this in GitHub
repo Secrets was rejected: GitHub Secrets are write-only outside Actions, and ECR
pull-through can't consume them — so Secrets Manager for creds + Parameter Store
for the host is both required and simpler.)*
**Consequences.** One declarative, ordered, self-healing source of truth; argo
upgrades and app changes are diffs. Adds the bootstrap seam (chicken-and-egg
install), a deploy-key to rotate, and the sentinel/render step for the account-
bearing host until the ApplicationSet/Harbor pattern is adopted.
