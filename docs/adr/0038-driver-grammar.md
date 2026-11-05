# ADR-0038 — The driver grammar: one mode, one verb

## Status

Accepted (BACKLOG item 37, Q234–Q243, built) · **Date:** 2026-11-05 ·
**Extends:** ADR-0022 (the driver), ADR-0025 (the sync switch), ADR-0037
(break-glass mode) · **Supersedes:** the verbs of the ADR-0025 item-13
amendment (`sync off`, `sync on`, `apply`) and of ADR-0037 (`hold`,
`release`, `reader_on`, `reader_off`)

## Context

The driver's arguments grew one item at a time: `up`, `next`, `down`,
`status`, `check` (ADR-0022), `sync off`, `sync on`, `apply` (item 13),
`hold`, `release`, `reader_on`, `reader_off` (pass 6b). Nouns named some
things and verbs named others, and the environment was the first word.
BACKLOG item 35 renamed `hold`/`release` to `pause`/`resume`. The user
tried the result and saw two things. The sync verbs and the break-glass
pair move one switch, so they were one thing with two names: the only
differences were the elevation, which does not matter on local, and the
record. And the inconsistency between nouns and verbs is complexity that
a user sees. Item 35 was dropped (Q234) and this item took its place.

## Decision

- **One grammar: `BRZL_ENV=<env> driver.sh <mode> <verb>`** (Q235, Q239).
  The first word is a mode, the second a verb. Target states (`on`,
  `off`) are not used. Verbs are. `BRZL_ENV` selects the environment
  definition, with a default (Q240): `local` until BACKLOG 38 renames the
  environment to `dev`. The driver refuses an unknown environment and
  lists the definitions in `env/`.
- **Three modes.** `cluster`, the usual mode (Q239): `bootstrap`,
  `teardown`, `status`, `check`. `break-glass` (Q237): `open '<reason>'`,
  `apply [<dir>]`, `close [confirm]`. `audit` (Q238): `bootstrap`,
  `teardown`, which start and stop the reader of the admin log store.
  `start` and `stop` are synonyms of `bootstrap` and `teardown`.
- **`next` is gone** (Q236). `cluster bootstrap` already resumes at the
  first phase with no `.ok`, and the preview shows every remaining phase.
  If one phase at a time is wanted later, it is `cluster run <phase>`.
- **The sync verbs fold into break-glass mode** (Q237). `apply` refuses
  unless the break-glass is open: that refusal is the guardrail that
  Q224 asked for. `close` syncs each kustomize Application from git
  before it moves the switch, as `sync on` did. `apply <branch>` is not
  a verb: it would mean two different things.
- **The teardown guard** (Q238 the user, Q244). `cluster teardown` and
  `audit teardown` emit every line behind the prefix `## ⚠ ##`. The first
  line sets a variable, behind the prefix too. The last group has no
  prefix, and it tests the variable. When the variable is not set, the
  group prints how to strip the prefix (`sed 's/^## ⚠ ##//'` in the pipe)
  to stderr, from a heredoc, and exits 2. So a pipe without the `sed` runs
  nothing and says so, and a pipe with it runs the teardown in silence.
  The message comes from the run, not from the emitter, so it cannot show
  when the `sed` is there. The recorded run sheets in `var/run/` are
  written when the stream runs, so they carry no prefix.
- **Who opens** (Q241). Sign-on names the person when it answers. When it
  does not, the record names the declared name, else the account on the
  operator's machine, as declared, not verified, with a warning. One rule
  for every environment.
- **The names follow** (Q243). `modes/reader.sh` is `modes/audit.sh`,
  and `modes/sync.sh` is gone. The run sheets are `break-glass-open-<UTC>Z`
  and `break-glass-close-<UTC>Z`. The reader's run directory is
  `audit-<UTC>Z`. The alert is `BrzlBreakGlassOpen`. The containers are
  `brzl-audit-<env>-loki` and `-grafana`. The annotation
  `brzl.dev/break-glass` and the binding `brzl-break-glass` keep their
  names. Records from before the change keep the old names.

## Consequences

- Every document that shows a driver command changed. The vocabulary is
  in GLOSSARY ("Driver command", "Break-glass mode", "Audit mode").
- The local dev loop is `break-glass open '<reason>'`, `break-glass
  apply` as often as needed, `break-glass close`. Each loop leaves a
  record, which the sync verbs did not.
- An operator cannot run one phase at a time. The preview shows them all
  before the pipe runs them.
- The guard adds one `sed` to each teardown command in the documents.
- `BRZL_SUBSTRATE=k3d` and the name `local` for the environment are
  BACKLOG 38, before pass 8: `local` names a substrate, and `k3d` a
  control plane.
- *Alternatives considered.* `readonly` as the third mode (the user's
  first name): `audit` says what the reader is for, and `readonly` is a
  Bash keyword. `subject` as the name of the first word: "mode" is what
  break-glass mode already is, and the usual mode gets a name. A default
  of `dev` now: it needs the rename of BACKLOG 38 first.

## As built (item 37, 2026-11-05)

- `driver/driver.sh`: `main` reads `BRZL_ENV`, then `<mode> <verb>`.
  `guarded` wraps the two teardown emitters (the variable `guard`). The
  emitted check call is
  `BRZL_ENV=<env> bash driver/driver.sh cluster check <phase> <run_dir>`.
- `driver/modes/break-glass.sh`: `open`, `open_check`, `apply`, `close`,
  `close_check`, with `kustomize_apps` and `local_source` from the old
  `sync.sh`. `driver/modes/audit.sh`: `audit_bootstrap`,
  `audit_bootstrap_check`, `audit_teardown`, `audit_teardown_check`.
- `driver/tests/driver-cases.sh`: 37 cases, with the grammar, the old
  verbs refused, the guard with and without the `sed`.
- Not tested live on 2026-11-05: `open`, `apply` and `close` need a
  cluster with sign-on.
