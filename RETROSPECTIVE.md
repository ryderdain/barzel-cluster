# RETROSPECTIVE — episodic record (append-only)

The durable, self-referential record of **completed, fully-validated,
user-verified** work. Think episodic/declarative memory, in contrast to the
working memory in [SCRATCHPAD.md](SCRATCHPAD.md) and the agent's internal
MEMORY index — this file is the more expansive source of truth.

**Contract:**
- An entry is written only when the work is done, validated, and the user has
  verified it. Plans live in [BACKLOG.md](BACKLOG.md); in-flight notes in
  [SCRATCHPAD.md](SCRATCHPAD.md).
- Entries carry a timestamp and are **append-only**: a record, once set, is
  never changed. Corrections and follow-ups are NEW entries that reference the
  old one — later memories may reference, expand on, or supersede earlier ones,
  additively.
- Reference entries by their timestamp heading.

---

## 2026-06-10 — Founding record: inherited ground truth

This repository is the post-delivery snapshot of a Lead Infrastructure Engineer
take-home, repurposed as its own project. Verified state at founding:

- **Platform proven end-to-end on AWS, twice over:** dev (public-subnet model)
  validated 2026-06-04 and again from-zero 2026-06-09; **prod (private-subnet
  nodes, NLB-only ingress, ADR-0019) built and validated live 2026-06-10** —
  7/7 ArgoCD apps Synced/Healthy including monitoring, demo-app served through
  the Terraform NLB.
- **Operator lifecycle proven:** CNPG failover drill (2026-06-04, zero data
  loss) and the full DR restore drill (2026-06-08: total teardown → fresh stack
  → restore from S3 alone → exact acceptance counts 4/84/423/84), both
  conductor-driven.
- **Account torn to zero** 2026-06-10 (third full retirement); every teardown
  snag is procedure in `docs/TEARDOWN.md` (§3a manual finishers).
- **Migration:** all `enclv` naming → `brzl`; vendor references removed; the
  external notes folded in as `notes/`; ArgoCD manifests point at this repo
  (`ryderdain/barzel-cluster`). The new `brzl-*` resource names take effect on
  the next from-zero bring-up. The ArgoCD deploy key's public half still needs
  registering on this repo before any GitOps bring-up.
- The take-home's hiccup ledger (13 entries, with fixes and doc destinations)
  is preserved at `notes/PROD_RUN_REPORT.md`; the delivery-day session log is
  the final entry of `notes/LLM-CONDUCT.md`.
