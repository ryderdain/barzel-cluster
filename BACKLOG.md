# BACKLOG — planned work (shared)

The explicit plan-of-record, edited by **both** the user and the agent. Items
land here when decided, move to [SCRATCHPAD.md](SCRATCHPAD.md) while being
worked, and produce a [RETROSPECTIVE.md](RETROSPECTIVE.md) entry when done and
user-verified.

## Active

- **Consolidation daemon** (spec: [CONSOLIDATION_DAEMON.md](CONSOLIDATION_DAEMON.md),
  2026-06-12) — semantic vault tier (`~/Local/github.com/ryderdain/aroni`) +
  SINBAD-gated promotion from episodic records, human-arbitrated. Build order
  §7; first milestone §8 (the 13 hiccups through the gate, one logged verdict).
  Step 0 scaffold staged 2026-06-12.

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
- `platform.sh` `operator()` phase: comment claims it installs EBS CSI + gp3,
  body doesn't (open since the A2 drill). → item 1
- Driver hardening: preflight per-layer `backend "s3"` blocks (a missing
  backend.tf silently applies to local state); print "next phase: X" on any
  phase failure. → item 1
- Generalize local-first state + `init -migrate-state` promotion as the
  bootstrap-from-zero mechanism (and its reverse for retirement) — noted in
  `docs/TEARDOWN.md` §3 / `docs/BOOTSTRAP.md` Phase 0. → items 1, 3
- Conductor repo-read credential (fine-grained PAT, Contents+Metadata) to
  replace the S3 tree-ship one-off. → item 1
- Register this repo's deploy key (public half) before the first GitOps
  bring-up here.
- ECR/Harbor image vulnerability scanning gate (scan-on-push, fail-on-critical).
- Re-enable Alertmanager with a real receiver (one-line flip, needs a target).
