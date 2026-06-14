# BACKLOG — planned work (shared)

The explicit plan-of-record, edited by **both** the user and the agent. Items
land here when decided, move to [SCRATCHPAD.md](SCRATCHPAD.md) while being
worked, and produce a [RETROSPECTIVE.md](RETROSPECTIVE.md) entry when done and
user-verified.

## Active — the major refactor (next barzel session) + aroni assists

**The refactor is the next focus** (items 1–4 below: automation overhaul vs
`notes/GUIDANCE.md`; env DRY/consolidation; multi-account CI). **aroni should drive
it forward** — and the refactor will *generate aroni's next corpus*: every decision,
failure, and fix is an episode. Log them (RETROSPECTIVE / a build ledger) as you go;
consolidate periodically. Watch for the first **co-firing** between existing notes —
that's the event that admits cand-005 and exercises the closed loop for real.

## aroni (consolidation daemon) — machinery complete through 2nd order

Self-contained shared vault at `~/Local/github.com/ryderdain/aroni` (b5744e3): 4
admitted notes, 17 episodes, doctrine (subordination, seam test, intersection test,
co-fire loop — all in METHOD), survival hooks, portable (`init_project`). The
co-fire re-evaluation loop is **closed + enforced** (vault_check + intersections
--work-order). cand-005 (first 2nd-order note) is HELD pending a real co-firing.
Open threads:

- **Next cycle:** ingest the 3 new surprise-0 RETROSPECTIVE episodes; normal pass.
- **Fully automating the co-fire re-gate** (vs the current detect+enforce, judge-by-hand)
  — only if it ever proves a bottleneck; the judgment is deliberately human.

- **aroni `lift` is not calibrated across models/sessions** (ordinal, judge-relative).
  A future "re-gate with one judge" pass before any cross-pass score comparison.
  Tabled 2026-06-14. (At second order, lift is already demoted to a sanity check.)
- Seeds: fix-propagation bundle (h3 + a sibling, needs a 2nd episode); cand-005 admits
  on its first demonstrated co-firing; cand-001/003 refinement (arbiter-flagged).

## Planned (user, 2026-06-10 — in intended order)

1. **Automation-methodology overhaul.** Bring all tooling — `platform.sh`
   itself included — into closer adherence with `notes/GUIDANCE.md`. Expect
   multiple passes; this will not complete in one.
2. **Polish `notes/GUIDANCE.md` itself** — as much for the user as for the
   agent.
3. **Environment realignment.** Simplify and consolidate the operational
   paths: bootstrapping on local, dev, and prod; bring dev and prod together
   DRY (today they are ~90% duplicated trees — the ApplicationSet divergence
   bug of 2026-06-10 is the standing argument).
4. **Multi-account CI design.** Expand the brzl demo model to showcase
   local-dev → infra-test → full-with-app-staging → full-prod across accounts
   — the piece the take-home never reached; have it ready to deliver for a
   similar interview.

## Carried over from the take-home (post-delivery candidates)

Most fold naturally into the numbered items above; tracked here until they do.

- Root-app pattern for the ApplicationSet (close the GitOps seam — ADR-0019
  names the design: include-glob `applicationset.yaml` + `project.yaml`,
  exclude `in-cluster.yaml`). → item 3
- ~~`platform.sh` `operator()` phase: comment claims it installs EBS CSI + gp3,
  body doesn't (open since the A2 drill).~~ → item 1 — **DONE (pass 1, pending live
  verify):** `operator()` now installs EBS CSI + gp3 via the new
  `gitops/bootstrap/install_ebs_csi.sh` (emit-style, renders the SAME committed
  ebs-csi values the ApplicationSet wave 0 uses → can't drift), then asserts the
  gp3 class exists before continuing. RECOVERY.md Step 4 updated.
- ~~Driver hardening: preflight per-layer `backend "s3"` blocks; print "next
  phase: X" on any phase failure.~~ → item 1 — **DONE (pass 1, pending live verify):**
  `preflight()` now asserts every layer declares `backend "s3"` (missing = silent
  LOCAL state); `_run_phases` prints the stopped phase + exact resume command (+
  phases not reached) on any failure, dual-mode (EXIT trap for direct runs,
  return-catch when sourced — no parent-shell trap pollution).
- **Pass-1 also:** renamed `generate-inventory.sh` → `generate_inventory.sh`
  (snake_case rule; all live callers updated, `notes/` history left as-is).
- **Discovered (→ item 3, env-DRY / aroni cand-002 env-coupling):** the shared
  `gitops/infrastructure/ebs-csi/values.yaml` hardcodes the `brzl-dev-k8s`
  pull-through prefix; both dev AND prod ApplicationSets (and now the standalone
  DR install) consume it, so prod's CSI sidecars pull through a `brzl-dev-*`
  repo. The whole recovery path is similarly dev-pinned (`cluster-recovery.yaml`
  → `brzl-dev-github`). Left faithful for now (changing it would diverge the
  standalone path from GitOps); fix env-wide in item 3.
- Generalize local-first state + `init -migrate-state` promotion as the
  bootstrap-from-zero mechanism (and its reverse for retirement) — noted in
  `docs/TEARDOWN.md` §3 / `docs/BOOTSTRAP.md` Phase 0. → items 1, 3
- Conductor repo-read credential (fine-grained PAT, Contents+Metadata) to
  replace the S3 tree-ship one-off. → item 1
- Register this repo's deploy key (public half) before the first GitOps
  bring-up here.
- ECR/Harbor image vulnerability scanning gate (scan-on-push, fail-on-critical).
- Re-enable Alertmanager with a real receiver (one-line flip, needs a target).
