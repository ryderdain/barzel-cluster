# ADR-0030 — One substrate adapter interface; conformant Kubernetes only

**Status:** Accepted · **Date:** 2026-10-14 · **Moved from:** ADR-0022 (the
adapter rule) and SPEC §3 "platform-layer portability" (2026-10-07) ·
**Supersedes in part:** ADR-0001 (k3s is the default, not a requirement),
ADR-0024 (the "k3s stays on each substrate" line)

**Context.** The rule that each substrate has one adapter with the same
interface was recorded inside ADR-0022, and the rule that the platform layer
assumes nothing beyond conformant Kubernetes was only a SPEC line. ADR-0024
and ADR-0026 cite them separately. With the objective restated as a
workload-independent platform on any substrate (SPEC §1, 2026-10-14), this
is the main decision of the design and it needs its own record. Each cloud
provider is a separate substrate (Q119).

**Decision.**

- **One adapter for each substrate, with one interface.** The adapter makes,
  changes and removes the cluster on its substrate, and it makes the services
  that exist beside the cluster. It is the only code that knows the
  substrate. Today: `driver/substrates/k3d.sh`; pass 8 adds AWS and later
  others.
- **The adapter's outputs are the contract.** The platform phases consume
  only: the kubeconfig; the registry host and the pull-through prefixes for
  each upstream (ADR-0025); the cluster secret store, through the
  secret-store adapter functions (ADR-0026); and, from pass 6 and 5c, the
  admin log store's data location and the admin portal's entry point. An
  output that one substrate cannot give is a design fault in the interface,
  not a special case in a phase.
- **The platform layer assumes only conformant Kubernetes plus those
  outputs.** No dependency on components that k3s bundles (Traefik,
  ServiceLB, local-path) and none on one cloud's API. So a managed control
  plane (EKS, GKE, DOKS) can replace k3s inside one adapter later, and a
  violation is named in BACKLOG until it is removed (today: the legacy local
  SSO edge, replaced by ADR-0028).
- **One OpenTofu stack for each cloud substrate**,
  `terraform/stack/<substrate>/<layer>/`. Environments on that substrate are
  instances of the stack, set by their environment definitions (ADR-0020
  extended to several clouds).

**Consequences.**

- A new substrate is one adapter and one stack; the phases, the
  ApplicationSet and the docs do not change.
- Local (k3d) is a real substrate, not a special case, and it tests the
  interface first (ADR-0024).
- *Alternatives considered.* Per-substrate branches of the phases: drift.
  A substrate "profile" inside one stack: one stack that knows every cloud.
