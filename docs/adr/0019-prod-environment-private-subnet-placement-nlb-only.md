# ADR-0019 — Prod environment: private-subnet placement, NLB-only ingress

**Status:** Accepted · **Date:** 2026-06-10 · **Validated live 2026-06-10** · **Layout superseded in part by [ADR-0020]** — the *per-env-directory* form below (`terraform/environments/prod/`) is retired; the placement / NLB / tunnel *decisions* stand, now expressed as model-B inputs (`public_nodes=false`, `enable_public_ingress=true`) on the single-source stack. (7/7
apps Synced/Healthy on private nodes, demo-app served through the NLB).
**Context.** Dev placed nodes in public subnets (admin-/32-locked) for direct
operability. Environment separation wants prod to be the same modules
with the production posture: no public node surface at all.
**Decision.** `terraform/environments/prod/` composes the same modules with
private-subnet placement: no public IPs (`associate_public_ip_address=false`),
egress via NAT, node access unchanged over SSM (the agent's channel is outbound).
The kube-API is reached through a **driver-managed SSM port-forward**
(`gitops/tools/api_tunnel.sh`, invoked by every kubectl-using `platform.sh` phase;
kubeconfig server `https://127.0.0.1:6443` — in k3s's default TLS SANs, so cert
validation holds through the tunnel). The **only public surface is a
Terraform-owned NLB** fronting the demo-app UI: self-managed k3s has no AWS
cloud-controller, so a `Service` of type LoadBalancer would pend forever — the
NLB (prod `50-compute/ingress.tf`) targets a fixed NodePort (30080, patched onto
the demo-app Service by the prod ApplicationSet), with the node SG admitting that
port from the NLB's SG only and the NLB listener allowlisted to the operator /32
(`lb_ingress_cidr` widens it deliberately). Monitoring runs in prod via
**`values-prod.yaml`** — kube-prometheus-stack is the one chart whose committed
values carry the env-scoped pull-through prefixes, so each env gets a values file
kept in lockstep modulo prefix.
**Consequences.** The prod placement model is built and proven, not asserted;
promotion really is composition (same modules, different inputs). Costs: the NLB
(~$0.02/hr, in the churned compute layer on purpose) and the tunnel as an
operational dependency — owned by the driver, not operator memory.
**Known limitation (designed fix, post-delivery).** The ApplicationSet itself
sits *above* the GitOps line: applied at bootstrap, updated by `kubectl apply`,
not reconciled from git — the 2026-06-10 bring-up felt this three times. The fix
is the standard root-app pattern: a wave -1 cluster-config Application syncing
`gitops/clusters/<env>/` with an `include` for `applicationset.yaml` +
`project.yaml` only — `in-cluster.yaml` stays excluded because its live
host/bucket annotations are deliberately not in git (ADR-0016) and self-heal
would strip them. Related: the dev/prod ApplicationSets are largely duplicated
(a `hostParams` omission in the prod copy cost one live debug cycle); diff-review
them as a pair until they're generated from one source.
