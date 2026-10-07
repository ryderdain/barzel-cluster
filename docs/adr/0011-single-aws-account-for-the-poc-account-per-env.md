# ADR-0011 — Single AWS account for the PoC; account-per-env/customer for prod

**Status:** Accepted · **Date:** 2026-06-02
**Context.** Real isolation wants separate accounts; building AWS Organizations
now costs time the timebox doesn't have, and reproducibility is the eval criterion.
**Decision.** Single account for the PoC (dev live, prod stub); **account-per-env /
account-per-customer (AWS Organizations) documented as the prod model**, with the
cross-account `assume_role` seam shown in the identity HCL (`prod` provider alias).
**Consequences.** Fast, reproducible PoC; promotion to real isolation is a diff,
not a rebuild. The second account is not actually created.
