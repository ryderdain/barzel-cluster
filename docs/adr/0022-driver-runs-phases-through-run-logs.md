# ADR-0022 — The driver runs phases through run-logs

**Status:** Accepted · **Date:** 2026-10-07
**Context.** `gitops/tools/platform.sh` operates its commands directly. Thus
an operator cannot see a full phase before it starts. Its trap logic, which
starts a phase again, breaks easily. Its 700 lines mix substrate work and
general work. The emit-commands rule in `ryderdain/bash` applies to the leaf
scripts, but not to the driver.
**Decision.** Divide `platform.sh` into emit-style phase scripts and a thin
driver. The driver is also an emit script. Its output has one group for each
phase. Each phase group does these steps:

1. It gets the commands from the phase script and writes them to a run-log:
   `var/run/<env>/<YYYYmmddHHMM>/<NN>-<phase>.sh`.
2. It operates the run-log file and writes `<NN>-<phase>.rc`.
3. It operates the check of the phase and writes `<NN>-<phase>.ok` if the
   result is correct.

The driver does not ask questions. The approval of the operator is to
operate the output. `driver.sh <env> next` gives only the subsequent phase.
`driver.sh <env> up | bash` operates all the phases that are not complete.

A run-log puts its commands in `{ … }` groups. Each group is one anonymous
function for one object. Thus the reader sees the procedure as a sequence of
groups. A step gets a check only in two conditions. The first condition is
that a second run of its group can cause damage. The second condition is that
an unsuccessful step can make the condition of the system unclear. The exit
code does not tell if a phase did its work. The check of the phase tells it.
**It must be safe to operate each phase again.** To start again, the driver
finds the first phase that has no `.ok` file.
Phases give their outputs to subsequent phases as files. Some phases have an
effect on a different machine, or cost money. Do these phases one at a time,
and examine each phase before you operate it. Only phases with local effects
can all go together. Each environment has one environment definition, with
lines that have the shape `NAME=value`. An exported value replaces the
default, and the driver shows a warning. Each substrate has one adapter, and
all adapters have the same interface. The rules are in `ryderdain/bash`
STYLE.md §1.2, §1.11, and §1.12.
**Considered options.**

- Commands connected with `&&`. Rejected: the check is implicit, and it
  stops at the boundary between two streams.
- A check on each command. Rejected: the run-log output shows a dependent
  error. An idempotent command that finds its object in position is not an
  error. These checks only add noise to the preview.
- A large script that the operator copies to the host. Rejected: there is
  no preview.

**Consequences.** Each run keeps a full record. Phases must use commands that
give the same result when they operate again: `apply`, `upgrade --install`,
and saved plans. Each phase has a check. The `&&` rule in `notes/GUIDANCE.md`
and in `CLAUDE.md` is withdrawn.
