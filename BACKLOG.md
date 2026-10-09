# BACKLOG — planned work (shared)

The explicit plan-of-record, edited by **both** the user and the agent. Items
land here when decided, move to [SCRATCHPAD.md](SCRATCHPAD.md) while being
worked, and produce a [RETROSPECTIVE.md](RETROSPECTIVE.md) entry when done and
user-verified.

## Active — local-first refactor (designed 2026-10-07, grilling session)

Design settled with the user (Q1–Q45); summary in [SCRATCHPAD.md](SCRATCHPAD.md),
vocabulary in [GLOSSARY.md](GLOSSARY.md). Supersedes the ordering of items 1–4
below (their intent folds in). AWS is frozen until pass 8. Each pass: rule in
`ryderdain/bash` first where one is involved, then `SPEC.md` §3, then ADRs +
runbooks. Runbooks must give from-zero, upgrade, re-image, and
change-of-image-source steps.

0. **ADR migration.** Move ADR-0001..0020 verbatim from `docs/ARCHITECTURE.md`
   into `docs/adr/00NN-slug.md` (+ Status line); ARCHITECTURE keeps an index;
   update `CLAUDE.md` living-docs lines.
1. **Doctrine + `&&` sources.** In `bash`: emitted `{ … }` groups as anonymous
   functions (check only where a re-run harms), driver archetype, env-definition pattern, run-logs, approval
   rule, idempotent phases. `CLAUDE.md` bash section → refer to `ryderdain/bash`.
   Superseded banners on `notes/GUIDANCE.md` + the vault Doctrine Seed note.
   New ADRs 0021–0024 (kiesei driver/conductor; run-log driver; mimic-now
   services; local as first env).
2. **Driver skeleton + k3d adapter.** *(written 2026-10-09; live run pending)* `local.env`, run-log mechanics,
   `substrate_up`/`substrate_down`; replaces `k3d-up.sh`; rewrite
   `docs/LOCAL.md`. Rename toolbox → kiesei.
3. **External Zot + kiesei build/push + warm conductor.** For the driver to
   run from kiesei on k3d: add `k3d` + the `docker` CLI to the image; mount
   the engine socket in `kiesei-shell.sh`; rewrite the k3d kubeconfig server
   (`0.0.0.0:<port>` is unreachable from inside a container). Then drop the
   host k3d/helm prerequisite from docs/LOCAL.md.
4. **Argo on local (GitOps mode) + `fast_on`/`fast_off`.**
5. **OpenBao (Vault CE fallback) + ESO + `secrets` phase + store adapters**,
   with a write-then-read smoke test in `up`.
6. **Loki + Alloy + conductor log shipping.**
7. **`promote` phase** (digest + env-definition values along the chain).
8. *(AWS unfreezes)* AWS phases of `platform.sh` → the AWS adapter.

Standing concerns (check in every pass, do not lose):

- **Every phase must be safe to run again.** Resume depends on it
  (`ryderdain/bash` STYLE.md §1.11, ADR-0022). Review each new phase script
  for converging commands before it lands.
- **Platform-layer portability** (SPEC §3, from Q45). The platform layer may
  assume only conformant Kubernetes + adapter outputs, so EKS/GKE/DOKS can
  later replace k3s inside one adapter. Known violation: the local SSO edge
  uses Traefik `IngressRoute` CRDs (`gitops/clusters/local/sso/`) — move to
  standard `Ingress`/Gateway API when the SSO edge is next touched.
- **`notes/` history scrub** — decision pending with the user (rewrites
  published history; see SCRATCHPAD).
- **Port the seed's §1.10** ("a script's claims are part of its contract") to
  `ryderdain/bash` STYLE.md (number reserved).

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
  Also drain the two new **inbox** captures (2026-06-15): the brzl-dev-* standalone-path
  leak (cand-002 evidence) + the instances-vs-source-layout correction (cand-005 framing).
- **Hooks gap (→ aroni BACKLOG, 2026-06-15):** no hook auto-captured the in-session
  correction this session; it took a manual "aronize it". Capture still leans on operator
  memory — the dependency the method exists to remove. Tracked in aroni BACKLOG ("No
  auto-capture of in-session episodes"); sibling of the surprise-mis-tag gap.
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
   paths: bootstrapping on local, dev, and prod.
   **Reframed (user, 2026-06-14):** the goal is NOT to collapse dev and prod into
   one definition — the parallel same-root-structure trees are *the point* of a
   dev→staging→prod split: you prove the pre-production model + code in dev before
   applying it to the reputation-exposed prod. Over-DRYing them away destroys that
   promotion gate. So the real target is the distinction:
   - **Intentional separation — KEEP:** each env is its own independently-promotable
     instance (own state/tfvars, own ApplicationSet apply), so a change lands in dev,
     is validated, then promoted to prod. Real per-env differences (prod private
     nodes + NLB/NodePort, instance sizes, conductor is dev-only) stay explicit.
   - **Accidental coupling/drift — FIX:** shared code that hardcodes one env (the
     `brzl-dev-*` leaks into env-agnostic scripts), and hand-maintained near-duplicate
     files that silently DRIFT (the 2026-06-10 ApplicationSet divergence *bug*). DRY
     belongs in shared **modules/templates** (define once, instantiate per-env), not
     in merging the instances. The divergence bug argues for reducing the
     hand-maintained surface, NOT for one-file-for-both.
   **Direction chosen (user, 2026-06-15): model B** — single source per layer + per-env
   `backend.hcl` + `terraform.tfvars`, driver-enforced backend↔tfvars pairing. Keeps
   separate state + independent apply (the gate); kills drift; fits the per-env-backend
   convention + the item-4 multi-account roadmap. Workspaces (C) rejected (weak state
   isolation, fights multi-account, switch footgun). Per-env structural deltas stay
   explicit: prod-only NLB → `count`/`var.enable_public_ingress`; node placement → vars;
   `00-conductor` stays its own optional standalone layer. **Merge plan pending user review
   before execution** (prototype on `10-network` first, prove the pattern, then roll).
   Full live validation deferred to the batch live-pass; in pass-1 (item 3) the standalone
   DR path was already de-pinned (commit 6941c78).
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
  `gitops/bootstrap/install-ebs-csi.sh` (emit-style, renders the SAME committed
  ebs-csi values the ApplicationSet wave 0 uses → can't drift), then asserts the
  gp3 class exists before continuing. RECOVERY.md Step 4 updated.
- ~~Driver hardening: preflight per-layer `backend "s3"` blocks; print "next
  phase: X" on any phase failure.~~ → item 1 — **DONE (pass 1, pending live verify):**
  `preflight()` now asserts every layer declares `backend "s3"` (missing = silent
  LOCAL state); `_run_phases` prints the stopped phase + exact resume command (+
  phases not reached) on any failure, dual-mode (EXIT trap for direct runs,
  return-catch when sourced — no parent-shell trap pollution).
- **Pass-1 also:** renamed `generate-inventory.sh` → `generate-inventory.sh`
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
