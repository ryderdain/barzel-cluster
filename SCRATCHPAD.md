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

*(2026-10-22, opus. Pruned to the current state. The history is in git,
the plan in [BACKLOG.md](BACKLOG.md), the records in
[RETROSPECTIVE.md](RETROSPECTIVE.md).)*

**Pass 6, item 4a and BACKLOG 20 DONE and user-verified**
(RETROSPECTIVE 2026-10-21 and 2026-10-22), merged to `main`. Logs with
two Loki stores and mutual TLS between the collectors; metrics and
Grafana on every substrate; sync retries with no limit, a warning in
phase 40 and the alert `BrzlSyncFailing`. The local cluster is up.

**Facts to keep in mind:** a portal location must not set its own
`proxy_set_header`. Loki with auth off stores everything under the tenant
`fake`. The store's CA is made in phase 10; the PKI role `portal` is
server-only. An Application keeps its last operation record (phase,
retry count) after its resources converge. The conductor scales itself to
zero after 30 minutes idle; `conductor.sh` claims a live pod. A stacked
graph hides series at 0.

**▶ IN FLIGHT: pass 6a, sign-on** (BACKLOG item 5), branch
`pass-6a-sign-on`, design round. Decided 2026-10-23:

- Q169: tier membership from GitHub teams in the organization (`tzvat`).
- Q170, Q173: three tiers, `admins`, `operators`, `auditors` (read
  everything, change nothing). GLOSSARY updated. A tier for workload
  developers (Grafana, workload logs only) waits for a real developer.
- Q171: the gate (nginx `auth_request` to oauth2-proxy) for every path, and
  Argo CD and Grafana each a Dex client (OIDC). No header trust.
- Q172: Dex at `https://<portal host>/dex/`.
- Q174: `kubectl` through Dex is a second step of this pass, after web
  sign-on is tested. BACKLOG 23: the cluster-admin kubeconfig on a cloud.
- Q175: the built-in Argo CD and Grafana logins are turned off; the
  emergency path is the CLI with the cluster-admin kubeconfig.
- Q176: a GitHub OAuth App per environment, owned by the organization.
  SECURITY.md states the wider `read:org` scope and compares an OIDC
  provider.
- Q177: sign-on in every environment, no switch. ADR-0028's "also works
  without it" (from the user's Q108 answer) goes; amend ADR-0028 and
  ADR-0035 when the round ends.
- Q178: Dex and oauth2-proxy from their Helm charts, namespace `sign-on`;
  Dex keeps its state in memory.
- Q179: the gate admits only the three teams. BACKLOG 24: a workload
  viewer tier, which the gate must be able to admit later.
- docs/SECURITY.md rewritten for drift, with the auth-flow diagrams.
- BACKLOG 22: the GitHub dependency, examined alone.

- Q180: the host steps (resolver file, CA trust) become a host run sheet
  that `driver/kiesei.sh` runs with `sudo` after phase 10, with a one-time
  confirmation in the run sheet; laptop substrate only. CA trust tested in
  containers 2026-10-23: Debian/Ubuntu/Alpine `/usr/local/share/
  ca-certificates/*.crt` + `update-ca-certificates`; Fedora/RHEL
  `/etc/pki/ca-trust/source/anchors/` + `update-ca-trust`; openSUSE
  `/etc/pki/trust/anchors/` + `update-ca-certificates`; Arch `trust anchor
  --store`. `trust anchor` fails on Ubuntu, so no one command for all.
  Chosen by `/etc/os-release` (`ID`, `ID_LIKE`). Browsers on Linux keep
  their own NSS store (not tested here). macOS: login keychain, as now.
- Q181: a rough decision log, local-only in `notes/DECISIONS.md` (user,
  2026-10-23: not in the repo for now); backfilled from the transcript.

Next: Q182 (team names per environment), Q183 (the access script makes the
teams). Then build step 1 (web sign-on).
BACKLOG 21 (an alert channel) fits with 6a or later.
