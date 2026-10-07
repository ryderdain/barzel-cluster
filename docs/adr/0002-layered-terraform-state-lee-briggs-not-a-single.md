# ADR-0002 — Layered Terraform state (Lee-Briggs), not a single root

**Status:** Accepted · **Date:** 2026-06-01
**Context.** A flat root couples unrelated resources, inflating blast radius and
plan times; `50-compute` churns far more often than the network.
**Decision.** Split state per rate of change (`10-network`…`50-compute`), per
environment, wired with `terraform_remote_state`; remote state in S3 + DynamoDB
lock; strict dev/prod separation.
**Consequences.** Small, fast, low-risk plans; compute can be destroyed between
sessions without touching the network. More wiring (remote-state lookups, apply
ordering) to maintain.
