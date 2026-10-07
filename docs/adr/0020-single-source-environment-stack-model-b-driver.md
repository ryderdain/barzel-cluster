# ADR-0020 — Single-source environment stack (model B) + driver-composed state backend

**Status:** Accepted · **Date:** 2026-06-17 · **Offline-validated** (all six layers
`tofu validate`-clean; driver wired) · **live validation pending** (greenfield — nothing
deployed). Supersedes ADR-0019's per-env-directory *layout*.
**Context.** dev and prod were near-duplicate per-env trees (`terraform/environments/{dev,prod}/<layer>`),
~90% identical. Hand-maintained copies *drift* — the 2026-06-10 ApplicationSet
`hostParams` omission (ADR-0019) cost a live debug cycle. But the dev→prod **promotion
gate** is *separate environment instances* — distinct state + independent apply — which
is **orthogonal to source layout**; duplicated source was protecting the wrong thing.
**Decision.** One source per layer under **`terraform/stack/aws/<layer>/`**, applied per
environment via a committed per-env **`<env>.tfvars`** (`-var-file`). State: **one S3
bucket + one CMK, environments split by the object key** `<env>/<layer>/terraform.tfstate`;
each layer's `backend "s3" {}` is empty and the driver (`platform.sh`) **composes** it at
`init -reconfigure` (bucket derived from the caller's account, key from `ENV`+layer) — no
per-env `backend.hcl`. Cross-layer `terraform_remote_state` derives the bucket the same
way and keys lower layers by `var.env`. **Intentional** per-env differences are explicit
*inputs*, not forks: 40-ecr's dev-only toolbox build (`repositories` + `toolbox_build_enabled`),
50-compute placement (`public_nodes`) and the demo-app NLB (`enable_public_ingress`,
count-gated — prod on, dev off, flag-flip to adopt). Committed `<env>.tfvars` hold only
non-secret defs; rendered secret/ARN tfvars use gitignored `*.auto.tfvars`. The conductor
+ `bootstrap`/`identity` stay account-primitives (own `backend.hcl`), not stack layers.
**Consequences.** Drift is structurally removed (one source; the per-env diff is two small
tfvars). Forward-compatible with multi-account (per-account buckets, conductor tied to its
account's state — SPEC §9). Tradeoff: a shared layer dir means `init -reconfigure` per env
switch (the driver does it), and "has prod's code caught up to dev's?" becomes a git-ref
question rather than a directory diff. Full detail: **SPEC §3** (model B + state backend),
**§9** (multi-account direction). Rejected: workspaces (weak state isolation, fights
multi-account, switch-footgun); keeping per-env dirs (the drift source).
