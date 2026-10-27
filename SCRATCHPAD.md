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
`pass-6a-sign-on`. Design Q169–Q185 (ADR-0035 amendment; the decision log
is `notes/DECISIONS.md`, local only). **Step 1, web sign-on: DONE and
user-verified 2026-10-23** (RETROSPECTIVE). Sign-out stays as it is
(Q185, BACKLOG 26); oauth2-proxy's trusted proxies are BACKLOG 27.

**2026-10-26: a throwaway round before Q186–Q188.** The user wants the
full view first: `notes/AUTH-FLOWS.md` (local only), in Mermaid. Part A:
the flows and secrets now, by scenario. Part B: the `kubectl` through Dex
proposal, and what it changes. Part C: production shapes against it. A
browser copy is `var/scratch/auth-flows.html`. Findings: Grafana has no
emergency path since sign-on (its login form is off). SECRETS.md could
carry a by-flow view. **Decided.** Q186 (a): one host alias to a fixed
portal ClusterIP. Q187 (a): the browser callback. kiesei already has the
host's network, and the step is once per sign-in. Q188 (a): phase 10
writes `kubeconfig-sign-on`. Q189 (a): kubelogin's cache under the run
directory. Q190 (a): `preferred_username` and `groups`, prefix `oidc:`.
**An outside review** (`notes/AUTH-FLOWS-FableAudit-202610261655.md`)
added conditions, taken on in BACKLOG item 5: the structured
`AuthenticationConfiguration` file, 1-hour ID tokens, `cookie_refresh`,
a PKCE check, and a NetworkPolicy for the admin Loki store. BACKLOG 28
to 31 hold the rest. Q191 (a): 1-hour ID tokens (Argo CD's UI asks for a
click every hour). **Step 2 built 2026-10-26, and `up` passed every check 2026-10-27**
after two fixes. The authentication config ran into the certificate
(ca.crt has no final newline), so awk writes it and phase 10 parses the
file. The substrate check looked for the host alias in CoreDNS too early,
so it waits now. The user ran phase 10 twice to confirm idempotency. The
documentation of the review is done (SECURITY.md has the roots, the
scenarios and the sessions, and SECRETS.md the per-root tables). The
sign-in checks remain, in four parts. **2026-10-27, later:** the sign-in
reached Dex (the token is right) and the kube-API refused it. A Docker
Desktop restart dropped k3d's `--host-alias` lines from the node and from
CoreDNS. So the node gets a k3d entrypoint script at every start, and the
pods get step 1's CoreDNS rule back (two mechanisms, ADR-0035). That needs
one more `down`, then `up`. Also found: Docker Desktop's "Enable host
networking" was off, so no callback could reach the browser. Q192 (a):
the browser callback stays in kiesei. A remote shell gets the device code
later (BACKLOG 32).

The live test, in four parts. `kubectl auth whoami` with
`kubeconfig-sign-on` shows `oidc:<login>`. The API audit log names the
person. An auditor has `view` only. The admin Loki pod stays Ready behind
its NetworkPolicy: k3s's policy controller and the kubelet's probes are
unverified, and if the pod goes NotReady, the policy needs an ipBlock for
the node. The old CoreDNS rule is gone, and the checks of phases 10 and 40
name the fixes.

**Next: step 2, `kubectl` through Dex** (Q174). A short design round
first. Facts: k3d v5.9.0 has `--host-alias ip:host` (it writes the nodes'
/etc/hosts and CoreDNS's NodeHosts); kubelogin is not in kiesei. The k3s
API server runs in the node's network namespace, where kube-proxy routes
a ClusterIP, so a host alias to a fixed portal ClusterIP would let it
reach Dex at the issuer URL, and could replace the CoreDNS rule. k3s
args are set at create: step 2 needs a new cluster.
BACKLOG 21 (an alert channel) fits with 6a or later.
