# ADR-0004 — Node access via SSM SSH-over-SSM, no inbound :22

**Status:** Accepted · **Date:** 2026-06-02
**Context.** Open SSH ingress is attack surface and key-management overhead.
The Ansible `aws_ssm` connection plugin avoids SSH but requires an S3
file-transfer bucket.
**Decision.** Access nodes via SSM Session Manager using an **SSH-over-SSM
ProxyCommand** keyed by instance-id; `20-security` leaves `:22` closed,
`30-iam` grants the node SSM permissions. The TF-generated key is break-glass only.
**Consequences.** No inbound `:22`, IAM-gated + audited access, no transfer
bucket, ordinary Ansible semantics. Depends on the SSM agent + an egress path
(NAT now; VPC interface endpoints documented for a no-egress prod posture).
