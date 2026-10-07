# ADR-0015 — Local-dev parity via k3d (built)

**Status:** Superseded by [ADR-0024](0024-local-is-the-first-environment.md) (2026-10-07) · **Built:** 2026-06-04 · **Date:** 2026-06-04
**Context.** A developer should be able to run the cluster + app stack on a laptop
for fast inner-loop work without paying the AWS compute/NAT meter. This is
uniquely cheap here: unlike EKS, **the same distribution runs locally** — k3d is
k3s-in-Docker — so local↔cloud parity is high and the GitOps layer (ArgoCD
app-of-apps, CNPG, ESO, demo-app) runs unchanged. We resolved the *design* now but
**deferred the build** to protect the delivery buffer — the required AWS spine and
depth (restore, monitoring, docs, leadership) are sized to the runway, and a local
path is a differentiator, not a TASK requirement.
**Decision.** Local dev targets **k3d** (highest-fidelity k3s mirror). A local
overlay flips exactly three things, all overlay/values changes rather than
refactors, so the manifests stay local-ready by construction:
- **Storage:** gp3 EBS CSI → **`local-path`** (k3d built-in) — already the
  documented descope lever (ADR-0009); CNPG/app `storageClass` is overridable.
- **Image pulls:** **retain ECR** (single source of truth + supply-chain story)
  via a short-lived `aws ecr get-login-password` → imagePullSecret (~12h TTL,
  re-run) or `k3d image import` for the handful of images — there's no instance
  profile on a laptop.
- **Backups:** CNPG → S3 **disabled locally** (`inheritFromIAMRole` needs the EC2
  profile); backup/restore stays an AWS-tested concern (the `barmanObjectStore`
  block is patch-removable).
**Consequences.** A laptop dev loop with real cloud parity, reinforcing the k3s
portability thesis (ADR-0003) — banked now for the architecture + leadership docs.
Build + test of the actual k3d bootstrap (+ a `LOCAL.md` runbook) is deferred to
post-delivery or spare buffer *iff* the AWS spine is already solid; the integration
debugging (ECR-from-local, storage, backup toggle) is deliberately off the delivery
critical path.
**Built (2026-06-04).** Pulled forward once the AWS spine, monitoring, and backups
landed early. Realized as a [`gitops/clusters/local`](../../gitops/clusters/local)
kustomize overlay + an emit-commands `k3d_up.sh`, applied directly with `kubectl
apply -k` (not the ECR-coupled ApplicationSet). One design point resolved on
contact: **images use upstream registries + a locally-built `demo-app:local`
(`k3d image import`)**, not the "retain ECR" option — the platform's account-id
host-injection is AWS-specific, so pulling upstream is cleaner and needs no AWS
creds (the ECR-import path is documented in [LOCAL.md](../LOCAL.md) as the alternative).
Verified end-to-end first try: CNPG on `local-path`, ESO projection, demo-app search
read/writes the local Postgres — with `AWS_PROFILE` unset. See [LOCAL.md](../LOCAL.md).
