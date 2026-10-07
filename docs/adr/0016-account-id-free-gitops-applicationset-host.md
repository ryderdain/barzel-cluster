# ADR-0016 — Account-id-free GitOps: ApplicationSet host injection at render

**Status:** Accepted · **Date:** 2026-06-04
**Context.** Committed GitOps manifests must not contain the AWS account id, yet
in-cluster image pulls go through ECR — and ECR auth (the kubelet credential
provider on the EC2 instance profile, ADR-0008) keys off the **real**
`*.dkr.ecr.*.amazonaws.com` host. A placeholder/mirror host breaks that auth (the
provider can't derive the registry; static `registries.yaml` creds reintroduce the
12 h ECR-token rotation we removed). So the real host **must** appear in the image
refs ArgoCD applies. ArgoCD reconciles a *rendered* desired-state and **self-heal
reverts post-apply edits**, so the host has to enter at **render time**, from a
source ArgoCD reconciles — not a bootstrap `--set` (that only reaches the initial
install) and not committed to git.
**Decision.** A **bootstrap shim** (`resolve_ecr_host.sh`) derives the host from
`aws sts get-caller-identity`; bootstrap writes the host **and** the backup-bucket
name onto the **in-cluster ArgoCD cluster Secret** as annotations
(`brzl.dev/ecr-host`, `brzl.dev/backup-bucket`) — live, never in git. The
app-of-apps is a single **`ApplicationSet`**: a `matrix` of a `clusters` generator
(selector-matched to that Secret, exposing the annotations) × an inline `list` of
the apps. Its `templatePatch` injects the host as **Helm `parameters`** for the
operator charts and as kustomize **`images`** (demo-app) / **`patches`** (CNPG
`imageName` + barman `destinationPath`) for the workloads. Committed manifests keep
the `__ECR_REGISTRY_HOST__` / `__BACKUP_BUCKET__` sentinels purely as documentation;
the rendered output carries the real values. Replaces the prior app-of-apps root +
the PoC sentinel-render escape hatch (the unresolved half of ADR-0013).
**Consequences.** The account id never lands in git and the injection is
self-heal-safe (it's part of desired-state). The bootstrap `--set` still covers
ArgoCD's own image (chicken-and-egg). Costs: one ApplicationSet with a
`templatePatch` (Go-templated, the documented way to express variable Helm params +
per-kind source shapes), an explicitly-registered in-cluster Secret (selector-scoped
so it doesn't duplicate ArgoCD's implicit local cluster), and two `kustomization.yaml`
files so the workloads accept render-time overrides. *Alternatives weighed and
dropped: a private config/ops repo (multi-source `$values`) — clean but a second
repo to run; a CMP `envsubst` sidecar — ideal for plain manifests but mutually
exclusive with native Helm sources, awkward for the operator charts.*
**Validated live (2026-06-04).** Brought up end-to-end: all six apps Synced/Healthy
by wave, host/bucket injection confirmed in the rendered `Application` sources
(Helm params, kustomize images/patches), demo-app read/writes the CNPG HA Postgres.
Two implementation lessons banked: **(1)** in a `matrix`, the `clusters` generator
injects a `name` parameter (the cluster name) that **shadows** any `name` key in the
`list` element — collapsing every app to the cluster's name (duplicate-`Application`
error) and silently disabling `eq .name "…"` branches in the `templatePatch`. Key
list elements on a non-colliding field (`appName`). **(2)** that collision had a
sharp edge: the single mis-named app carried the wave -1 self-manage element, so when
the corrected ApplicationSet **pruned** it, the finalizer cascade-deleted ArgoCD's own
config layer (`argocd-cm`, RBAC, ServiceAccounts) — recovered by re-running the
idempotent `helm upgrade --install` and restarting the controllers for fresh SA tokens
(see [RECOVERY](../RECOVERY.md#argocd-control-plane-self-inflicted-prune-)).
**Amendment (2026-07-07).** A pre-publication history audit (gitleaks + a
targeted grep — verifying this ADR's claim rather than trusting it) found the
account id **had** landed in git after all: not in manifests or tfvars (this
ADR's scope, which held), but in three `notes/` run-report/bring-up working
files, present since the repo's initial snapshot commit. Remediated before
publication with a full-history rewrite (`git filter-repo --replace-text`)
substituting documentation placeholders (`123456789012`, `i-0123456789abcdef*`)
for the real account id and the destroyed take-home instance/VPC/SG ids; the
rewrite was re-verified with gitleaks plus an all-blobs grep (zero occurrences).
Lesson: a hygiene claim is scoped to the surfaces it instruments — captured
terminal output in working notes was an uninstrumented channel.
