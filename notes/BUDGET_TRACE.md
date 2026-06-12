# BUDGET_TRACE.md — per-iteration cost visibility

**Local-only (gitignored).** Working ledger so I can see the expected spend of
each test iteration before bringing infra up, and log actuals after. Not a
deliverable — the cost *posture* lives in [`SPEC.md`](SPEC.md) §8 and the
teardown modes in [`docs/TEARDOWN.md`](docs/TEARDOWN.md).

> Prices are **approximate eu-central-1 (Frankfurt) list prices, ~2026-06**, on-demand
> unless noted. Reconcile against AWS Cost Explorer / the Pricing Calculator —
> treat these as planning estimates, not invoices. `≈` throughout.

---

## Per-hour component costs

| Component | Spec | Unit price | Qty | Per-hour |
|-----------|------|-----------|-----|----------|
| Compute — on-demand | `m6g.large` (2 vCPU / 8 GiB, arm64) | ≈ $0.0904/hr | 3 | **≈ $0.2712** |
| Compute — spot | `m6g.large` (typical ~60–70% off) | ≈ $0.030/hr | 3 | **≈ $0.090** |
| Compute — smaller lever | `m6g.medium` (4 GiB) on-demand | ≈ $0.0452/hr | 3 | ≈ $0.1356 |
| NAT gateway | managed, single | ≈ $0.052/hr | 1 | **≈ $0.052** |
| NAT data processing | per GB through NAT | ≈ $0.052/GB | — | usage |
| Public IPv4 (EIP) | charged in-use since 2024 | ≈ $0.005/hr | 1 | ≈ $0.005 |
| EBS gp3 root | 30 GiB × 3 nodes = 90 GiB | ≈ $0.0952/GB-mo | 90 GiB | ≈ $0.0117 |
| EBS gp3 PVCs (later) | CNPG 3× ~10 GiB | ≈ $0.0952/GB-mo | 30 GiB | ≈ $0.0039 |
| KMS CMK (state) | customer-managed key | ≈ $1.00/mo | 1 | ≈ $0.0014 (flat) |
| S3 state + DynamoDB lock | versioned / pay-per-request | ≈ $0 | — | ≈ $0 |
| ECR storage (later) | per GB-mo | ≈ $0.10/GB-mo | minor | ≈ $0 |

---

## Scenario roll-ups

**A. Live test session — compute UP (on-demand):**
`0.2712 (3× m6g.large) + 0.052 (NAT) + 0.005 (EIP) + 0.0117 (EBS root)`
≈ **$0.34/hr** + NAT data. → a typical 3-hr iteration ≈ **$1.02** (+ data).

**B. Live test session — compute UP (spot, iteration default):**
`0.090 (3× m6g.large spot) + 0.052 + 0.005 + 0.0117`
≈ **$0.16/hr** + NAT data. → a typical 3-hr iteration ≈ **$0.48** (+ data).

**C. Between sessions — `50-compute` destroyed, NAT + network kept up:**
`0.052 (NAT) + 0.005 (EIP)` ≈ **$0.057/hr** ≈ **$1.37/day** ≈ **$41/mo if left**.
→ destroy `10-network` too on longer pauses to zero this out.

**D. Standing/flat — regardless of compute:**
state CMK ≈ **$1/mo** + ECR CMK ≈ **$1/mo** (created 2026-06-02, layer 40) = **≈ $2/mo**;
S3/DynamoDB ≈ $0. (+ ~$1/mo for a future EBS CMK if added.)

**One-time per fresh bootstrap:** image/package pulls through NAT — e.g. ~5 GB ≈ **$0.26** of NAT data processing.

---

## Iteration log (fill actuals after each round)

| Date | Mode (spot/on-demand) | Up→down (hrs) | Est. cost | Actual (Cost Explorer) | Notes |
|------|----------------------|---------------|-----------|------------------------|-------|
| 2026-06-01 | — (bootstrap+identity only) | n/a | ≈ $1/mo CMK | — | state backend + OIDC roles; no compute yet |
| 2026-06-02 | n/a (10→40, no compute) | up @ ~16:?? | ≈ $0.057/hr (NAT+EIP) + ~$2/mo CMKs | — | VPC vpc-05a15d324cd30f52e + NAT nat-06e892221ba7a7172 + SG + node IAM + ECR live; ECR CMK 56d094d3 added; no compute yet |
| 2026-06-02 | spot (FAILED) | ~21min thrash | ~$0 (negligible) | — | 50-compute spot m6g.large reclaimed within ~7-8min (Server.SpotInstanceTermination ×2), never converged; SIGINT'd, state clean. Heavy spot pressure eu-central-1. EBS CMK af15c71a created (kept). |
| 2026-06-02 | on-demand (50 UP) | ~12:5x→13:46 (~1hr) | ≈ $0.34/hr (3×m6g.large OD + NAT/EIP/EBS) + ~$3/mo CMKs | — | 3× m6g.large running (i-0fe07509…, i-0f3a07de…, i-0024b9fb…), 1/AZ; full dev stack 10→50 live |
| 2026-06-02 | DOWN (50 destroyed) | back @ 13:46 | ≈ $0.057/hr (NAT+EIP) + ~$2/mo CMKs | — | 50-compute torn down (iteration). EBS CMK af15c71a → PendingDeletion 7-day window (del 2026-06-09, ~$0.23 orphan); shortened from 30d. Network/identity/state kept up. |
| 2026-06-02 | on-demand (SSM e2e test) | ~17:27→~18:1x (~45min) | ≈ $0.34/hr × ~0.75h ≈ **$0.26** | — | SSH-over-SSM keyless-access e2e: 3× m6g.large OD (i-0807f4b…/i-0e2c6fe…/i-047359c), :22 ingress removed, SSM policy on node role. Bootstrap (base+security) green + idempotent; sshd hardened no-lockout; NTP made cloud-agnostic (dropped AWS 169.254.169.123 → pool.ntp.org). Teardown = **instances only via -target** (first time keeping the EBS CMK): new EBS CMK 4805a479 left **Enabled** (no churn); NAT/network/state kept. (Prior CMK af15c71a still pending-del → 2026-06-09.) |
| 2026-06-03 | on-demand (k3s-HA e2e test) | up @ ~11:30, **still UP** | ≈ $0.34/hr (3×m6g.large OD + NAT/EIP/EBS) + ~$3/mo CMKs | — | k3s HA `kubernetes` role e2e: 3× m6g.large OD (i-0b1772910…/i-0b6d3472…/i-0b8a9c1b…), 1/AZ, reused retained keypair. Bootstrap green; cluster.yml → 3 Ready control-plane,etcd,master v1.31.5+k3s1, kubeconfig fetched + local kubectl reachable over public IP. **Compute left UP** pending keep-for-GitOps vs teardown decision. |

---

## Watch-items (cost leaks if teardown is incomplete)
NAT gateway, idle EIP, orphaned PVC-backed EBS volumes, LoadBalancer ELBs,
CMKs in pending-deletion (bill until window closes), state bucket/lock.
Full sweep checklist: [`docs/TEARDOWN.md`](docs/TEARDOWN.md) §4.
