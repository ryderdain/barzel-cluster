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

## 2026-06-12 — Consolidation daemon: §8 milestone, first gated admission

The full §7 steps 0–4 loop ran end to end and the user-as-arbiter issued the
first verdict. Verified state:

- **Vault live** (`aroni`, standalone repo): four passes landed via the
  scratch-worktree → ff-only mechanism (000 mechanics probe, 001 ingest,
  002 claim remap, 003 admission), each one atomic commit, pushed.
- **Ingest (§7.1):** `daemon/ingest_adapter.py` — 14 episode records (13
  hiccups, 1 retrospective), stable content-hash ids, idempotent (zero diff
  on re-run); surprise histogram {0:1, 2:10, 3:3}, masked failures
  auto-escalated. User decision folded in: `claim` = root-cause
  generalization (pass-002, no id churn).
- **Bundler (§7.2):** deterministic entity-rule clustering; 4 eligible
  bundles; known v1 noise (keyword match pulled the retrospective record
  into `argo_sync_ops`).
- **Gate (§7.3) + arbiter (§7.4):** cand-001 ("a success signal that does
  not assert the outcome is not evidence of success", children h5/h9/h12)
  scored lift +0.33 over 0.25 baseline (ordinal, self-judged per spec
  caveat), survived falsification after one boundary narrowing, and was
  **accepted** by the arbiter (bare accept; rationale recorded as none
  given). Admitted to `aroni/notes/` with provenance; decision in
  `aroni/decisions/pass-003.md`. cand-002 (env-coupling) drafted, queued.

## 2026-06-12 — Daemon operational: §7.5/§7.6 built, second admission (critic-narrowed)

- **§7.5 `vault_check.py`** (postcondition asserts: frontmatter, child links,
  supersession, decision pairing) and **§7.6 `scheduler.py`** (consumption
  derived from active notes — no state file) built and run clean; bundler's
  retrospective-record noise fixed (failure rules → `source=hiccup` only).
- **cand-002 admitted** (pass-004, the first vault_check-gated land): lift
  +0.25 over a 0.44 baseline. The gate's falsification seat **landed a hit on
  a child** — h2 was pre-empted at review, contradicting the draft's
  "runtime, serially" — and the claim was narrowed (audited→review /
  unaudited→runtime) before admission. Arbiter accepted the narrowed form
  with rationale: "the reasoning is sound" — the decision log's first real
  rationale.
- Queue after consumption: doc_drift (4 pending, priority 8) is the next
  drafting cycle; argo_sync_ops fell ineligible (2 pending).

## 2026-06-14 — aroni method formalized; doc_drift cycle (first revise verdict)

- **Method formalized** (user-directed, barzel `a92b712`): keyword **aroni**
  anchored in CLAUDE.md (vault + method); the repeated cycle codified as
  `daemon/ARONI_METHOD.md`. Two refinements: (1) candidates are surfaced in the
  vault (`aroni/_candidates/`, note + `.gate.md`) for the arbiter to read in
  Obsidian, never buried in chat; (2) verdict rationale is required for
  reject/revise + non-obvious accepts, **optional on a face-valid accept**
  (deferred refinement is the method, not a debt). New trays `_candidates/` +
  `gate_runs/` established (pass-005).
- **cand-003 admitted, REVISED** (pass-006 — first `revise` verdict, first
  substantive decision-log rationale). Gate ejected h3 (config fix-propagation,
  not doc rot; seeded forward) → narrowed to h1/h4/h8, lift +0.30. The claim was
  *face-valid* on rarity/time; the arbiter used the rationale-optional latitude
  to **sharpen causation** — rot is determined by **drift from
  last-validated conditions** (substrate + assumed use-context), not rarity (a
  non-causal correlate). h8 strengthened, h1 held, h4 retained via the
  context-drift dimension (boundary, confidence 0.65).
- **Corpus state:** 3 active notes (cand-001/002/003) consume 10 of 13 hiccups.
  Remaining 3 sit in now-ineligible bundles: h3 (seeded "fix doesn't propagate
  across parallel surfaces"), h11 + h13 (argo_sync_ops, 2 < the 3-child floor).
  The 13-hiccup fixture corpus is effectively exhausted; further consolidation
  awaits new episodes (or a second-order pass over the notes themselves).

## 2026-06-14 (later) — aroni made durable across sessions + portable across projects

- **Survival hooks** (user-directed): barzel `.claude/settings.json` gained a
  SessionStart hook that injects the SCRATCHPAD current-focus + the vault's last
  passes into every session (so state survives compaction and prose-compliance
  decay), and a PreCompact flush nudge. The store always survived (git); this
  makes the *practice* survive — and surfaces state to the human, whose cheap
  re-invocation is the real durability, not agent diligence.
- **aroni is now self-contained + shared.** The `daemon/` (tools + specs) moved
  out of barzel into the aroni repo (`tools/`, `SPEC.md`, `METHOD.md`); barzel is
  demoted to one *episode source*. One vault shared across all projects (universal
  beliefs transfer; per-project vaults rejected). Notes carry `scope:`
  (universal | project:<name>). Historical cand-001/002 gate runs + drafts folded
  into `aroni/gate_runs/` (pass-007), note provenance repointed in-vault.
- **Portability is one idempotent command.** `aroni/tools/init_project.py <repo>`
  installs the hooks (how they *travel*), scaffolds RETROSPECTIVE/SCRATCHPAD/BACKLOG,
  and emits the CLAUDE.md anchor; `aroni/ADOPTING.md` covers other repos *and* other
  domains (the method is domain-agnostic; only ingest is domain-coupled). ingest is
  now source-path explicit (retro-only path works for non-infra domains). A signature
  bug (PreCompact duplicated on re-run) was caught by dogfooding and fixed; hook
  strings are ASCII so machine-written settings.json is byte-stable.
- **Tabled** (BACKLOG): aroni `lift` is ordinal + judge-relative — not comparable
  across passes by different models without a single-judge re-gate.
- Commits: barzel `a92b712`→hooks/anchor; aroni `17e67a0` (self-contained move),
  `892aba4` (pass-007 provenance + scope). Consolidation state otherwise unchanged
  (3 notes, corpus bundle-exhausted).

## 2026-06-14 (late) — aroni's second order: doctrine, instruments, and a closed loop

The self-referential arc — the vault consolidating its own construction, and
growing a structure. All arbiter-verified in-session.

- **cand-004 (SSOT) admitted** (pass-011): an uncoupled redundant copy of a
  single-source fact diverges/drifts/is-lost. Reached the ≥3 floor by promoting a
  real take-home episode (derive-don't-store); the arbiter ruled the predicate
  broadening *correct generalization*, not a reach.
- **Subordination doctrine** (METHOD): when claims overlap, generate a higher-order
  claim that subordinates them (overlaps + distinctions explicit); narrowing is
  **failure-driven**, never preemptive; the aim is claims that re-bundle by point of
  contact so the model self-selects experience-laden context.
- **cand-005 "context-seam"** — the first **second-order** note (children are notes).
  "A property true in one context breaks on contact with a second; the bug lives in
  the *relation*, invisible from either side → instrument the seam, don't fortify the
  source." Made falsifiable by **the seam test** (a one-question seam/source
  classifier).
- **The second-order gate**, accepted after a deep `lift` explanation: lift is a
  *first-order* instrument (it makes concrete episodes mutually predictable); over
  claims it's a plausibility vibe → **demoted to a sanity check**. Second-order
  admission = (seam-boundary) AND (≥1 **demonstrated intersection** — an episode that
  is a child of ≥2 subordinates). Instrumented by `tools/intersections.py`.
- **cand-005 is HELD**: the intersection instrument finds **zero** co-firings, so its
  asserted intersections (h11=002∩004 — even excluded by cand-002's boundary) don't
  count. The instrument caught its author's over-reach on first use — the system
  holding its own builder to the standard.
- **Co-fire re-evaluation** (the user's instinct, verified + mechanised): a shared new
  child makes subordinates' lift stale → re-gate; the direction (hold/rise=wire,
  drop=narrow, persistent=merge) is the Hebbian signal. **The loop is closed +
  enforced**: `vault_check` fails any pass that lands an unacknowledged co-firing;
  `intersections.py --work-order` emits the tasks. Code detects+enforces; the model
  judges. Verified by dogfooding.
- Vault at aroni `b5744e3`: 4 notes, 17 episodes, 5 decisions, passes 000–013.
