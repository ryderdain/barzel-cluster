# Time Table — Actuals

Required time per sub-task, reconstructed from the working-session telemetry
(per-day activity windows), the git history, and the internal plan's per-task
ticks. Hours are honest approximations (±30 min), not stopwatch values.

**How to read the numbers.** Several long phases (live applies, the DR restore,
the from-zero validation run) were *gated agent runs*: the LLM drove, every
billable/mutating step waited on my approval, and I supervised intermittently —
sometimes approving from a phone. Wall-clock for those phases is therefore
longer than hands-on time; the table reports wall-clock engagement and flags
the heavily-gated runs.

## Per sub-task

| Sub-task | When | Hours |
|----------|------|------:|
| Planning, spec (SPEC/PLAN), repo scaffold | May 29 – Jun 1 | ≈ 4.0 |
| Terraform: state backend + identity/OIDC trust anchor | Jun 1 (eve) | ≈ 2.0 |
| Terraform: reusable modules, layered dev env, live applies; 15-kms foundation | Jun 2, Jun 4 | ≈ 4.0 |
| Ansible: `base` + `security` roles, inventory generator | Jun 2 | ≈ 3.0 |
| SSM keyless node access (SSH-over-SSM), live-tested | Jun 2 | ≈ 2.5 |
| Ansible: `kubernetes` role — k3s HA (3-server etcd), live-verified | Jun 3 | ≈ 3.5 |
| Operator toolbox image + bootstrap-VM cloud-init; ECR publish | Jun 2–3 | ≈ 3.5 |
| GitOps: ArgoCD bootstrap, ECR pull-through, node→ECR kubelet auth | Jun 3 | ≈ 3.5 |
| GitOps: account-id-free ApplicationSet (ADR-0016) + live bring-up + fixes | Jun 4 | ≈ 4.0 |
| CloudNativePG: HA cluster + S3 backups; failover + backup drills | Jun 4 | ≈ 3.0 |
| Demo app: Go+pgx REST API + ESO secret projection; Sefaria search evolution | Jun 4 | ≈ 4.5 |
| Observability: kube-prometheus-stack, CNPG + app/DB dashboards | Jun 4 | ≈ 2.0 |
| Local-dev (k3d) overlay + first full teardown | Jun 4 (night) | ≈ 2.0 |
| Conductor layer + sourceable A2 driver; script-doctrine consolidation | Jun 8–9 | ≈ 6.0 |
| **A2 DR restore drill** (rebuild → restore from S3 → acceptance PASS) + zero-footprint teardown — *gated agent run* | Jun 8 | ≈ 6.5 |
| **From-zero validation bring-up** + hardening fixes at source — *gated agent run* | Jun 9 | ≈ 7.0 |
| Docs: ARCHITECTURE + ADRs, runbooks, README passes | Jun 3–10 | ≈ 5.0 |
| Leadership answers + security considerations | Jun 9 | ≈ 3.0 |
| Delivery-day finalization (doc alignment, this table, review) | Jun 10 | ≈ 3.0 |
| **Prod environment: private-subnet placement + NLB ingress — built + validated live** (ADR-0019; user-driven, LLM-navigated) | Jun 10 | ≈ 4.0 |
| **Optional differentiator: operator SSO gateway (Dex→GitHub, local k3d)** | Jun 4–5 | ≈ 5.5 |
| **Total** | | **≈ 81** |

## Per day (session activity windows, CEST)

| Day | Window | Focus |
|-----|--------|-------|
| Fri May 29 | ~2 h | TASK analysis, plan, Terraform scaffold |
| Sat–Sun | ~0.5 h | off; brief off-desk review |
| Mon Jun 1 | 17:44–21:03 | spec iteration; state backend + identity applied |
| Tue Jun 2 | 09:17–18:02 | toolbox, layers live, Ansible roles, SSH-over-SSM |
| Wed Jun 3 | 09:51–20:00 | k3s HA role, ARCHITECTURE/ADRs, ArgoCD foundation |
| Thu Jun 4 | 07:34–24:00 | MVP complete + failover/backup drills + monitoring + k3d (longest day) |
| Fri Jun 5 | intermittent | SSO live bring-up (optional layer), A2 runbook |
| Sat–Sun | — | off (Jun 7 held as buffer, not needed) |
| Mon Jun 8 | 10:09–20:48 | conductor + A2 DR restore drill (PASS) + teardown to zero |
| Tue Jun 9 | 11:41–23:35 | from-zero validation bring-up, leadership/security docs |
| Wed Jun 10 | 08:36–~16:00 | delivery finalization; prod env built + validated live (private subnets, NLB) |

## Plan vs. actual

- **MVP** (infra → k3s → GitOps → CNPG → app, end-to-end): promised internally
  for Fri Jun 5; **landed Thu Jun 4** — the saved day went to monitoring and the
  k3d local-dev path.
- The two self-imposed differentiators (constrained-identity OIDC, the
  toolbox/conductor) cost roughly a day combined and repaid it on Jun 8–9, when
  the DR drill and the from-zero validation ran entirely through them.
- Sunday Jun 7 buffer was never drawn down; the Jun 10 buffer absorbed exactly
  what it was held for (doc alignment, this table).
