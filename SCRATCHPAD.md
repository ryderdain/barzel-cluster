# SCRATCHPAD — working memory (volatile, user-exposed)

The agent's short-term store: session comments, considerations, partial
conclusions, and state worth surviving a context compaction — kept here so the
user can see (and correct) the working memory at any time. Works **in tandem**
with the agent's internal cycles, not instead of them.

**Contract:**

- Freely written and rewritten during a session; stale content is pruned, not
  preserved. Nothing here is a record — durable outcomes graduate to
  [RETROSPECTIVE.md](RETROSPECTIVE.md) once user-verified; planned work moves
  to [BACKLOG.md](BACKLOG.md).
- Update it at natural checkpoints: when picking up a task, on a significant
  finding or direction change, and before ending a session.
- The user may edit or annotate at will; treat their text as instruction.

---

## Current focus

*(2026-10-15, fable. Pruned to the current state; the history is in git,
the plan in [BACKLOG.md](BACKLOG.md), the records in
[RETROSPECTIVE.md](RETROSPECTIVE.md).)*

**Pass 5c DONE and user-verified**, merged to `main` (RETROSPECTIVE
2026-10-15, two entries). The portal is at `https://local.barzel.sh/`
(Argo CD `/argocd/`, demo-app `/apps/demo-app/`); Argo CD v2.13.4 (chart
7.7.23); cert-manager v1.21.2 with the `vault` issuer to OpenBao's PKI;
default local host `brzl-<env>.localhost`, the DNS stand-in only for a
chosen name (ADR-0036); `bash driver/kiesei.sh shell` for the CLI tools;
operator steps print in a boxed block (`operator_step`, `BRZL_HOST_OS`).
The cluster follows `main` (run `202610151255` and later). Guidebook drafts:
`docs/guide/{kustomize,cert-manager,kiesei}.md` (BACKLOG item 12).

**Facts to keep in mind:** the ApplicationSet file is applied by phase 30,
not followed from git (BACKLOG 15); an old store must be purged when the
`driver` policy changes; checks run in kiesei (Linux, no `dig`, cannot see
macOS); the demo-app's `/apps/demo-app/` uses an nginx `sub_filter` until
5d replaces it.

**▶ NEXT: pass 5d, the example app** (chofesh; ADR-0034; BACKLOG item 3,
"keep it short" — user). Start with a short design round: the server mode
of `ryderdain/chofesh` (the demo-app's REST API, a small page, Postgres),
its sub-path setting for `/apps/chofesh/`, the Postgres cluster moving
into the app, the ApplicationSet element and registry image, what of
`apps/demo-app` and `gitops/applications/demo-app` goes. The user switches
to Opus 5.5 for this pass.
