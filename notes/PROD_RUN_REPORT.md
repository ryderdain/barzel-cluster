# Prod Bring-up (private subnets + NLB) — Run Report

Live validation of the prod placement model: private-subnet k3s, no public node
IPs, kube-API via SSM port-forward, Terraform NLB fronting the demo-app UI alone.
Personal run log (gitignored), companion to `A2_RUN_REPORT.md`. **Every hiccup
lands here with its in-place fix and its doc destination, so the final
refinement pass folds all of them into the delivery docs + LLM-CONDUCT.**

- **Run started:** 2026-06-10 (delivery day; user drives, LLM navigates)
- **Account state at start:** zero (post Jun-8/9 full teardown)
- **New code under test:** `terraform/environments/prod/` (6 layers, incl.
  `50-compute/ingress.tf` NLB), `gitops/clusters/prod/` (3 manifests),
  env-parameterized `bootstrap_argocd.sh`

---

## Hiccup ledger

| # | Phase | Symptom | Root cause | Fix applied | Doc destination |
|---|-------|---------|-----------|-------------|-----------------|
| 1 | Phase 0 — `terraform/identity` `tofu init` | "state data in S3 does not have the expected content" (empty expected digest) | The Jun-8/9 teardown removed the state **buckets** (manual sweep) but the DynamoDB lock table survived with 8 stale `*.tfstate-md5` **digest rows**; fresh bucket + old digests = mismatch on next from-zero init | Scanned the table, deleted all 8 stale digest rows; init then clean | **DONE** — TEARDOWN.md §4 leak sweep gained the digest-row item (observed 2026-06-10) |
| 2 | (pre-empted) GitOps bootstrap | `bootstrap_argocd.sh` had 4 hardcoded `brzl-dev` refs (quay image path, backup-bucket SSM param, in-cluster Secret name, manifests dir) — guaranteed prod failure | Script predates the prod env | Parameterized by `ENV` (default dev), shellcheck clean — fixed before the run rather than during | LLM-CONDUCT (today's entry); no runbook change needed |
| 3 | Conductor SSH-over-SSM | `Too many authentication failures` on the emitted ssh command | ssh-agent offers its keys first and exhausts `MaxAuthTries` before the `-i` key — the SAME bug fixed 2026-06-02 on the node path (`ansible.cfg` has `IdentitiesOnly=yes` + `PreferredAuthentications=publickey`); the conductor's emitted command (`00-conductor/outputs.tf:13` `ssh_over_ssm_command`) never got the flags | User-fixed at source: both flags added to the output string | LLM-CONDUCT; ACCESS.md if it documents the conductor ssh command verbatim — check in the final pass |

| 5 | `layers` phase — 50-compute plan | `Unable to find remote state` for `prod/20-security.tfstate`, though 20-security "applied successfully" | **LLM authoring miss:** prod/20-security was written without a `backend.tf`, so `init -backend-config` had no backend block — the layer silently applied into LOCAL state on the conductor; S3 never got the state object. The driver didn't fail on the no-backend warning | `backend.tf` added to the repo; on the conductor: write the same file, `tofu init -migrate-state` (copies local→S3), verify `state list` + the S3 object, resume `layers` | LLM-CONDUCT. Hardening follow-up: `platform.sh layers` should preflight that every layer dir has a `backend "s3"` block (or escalate tofu's no-backend warning) so local-state fallback can never pass silently |
| 4 | Conductor — `secrets` phase | Run stalled on missing `GHCR_*`/`DOCKERHUB_*` exports; while re-minting, no doc said WHICH token shape to mint (classic vs fine-grained, which scopes) | BOOTSTRAP.md only said "read:packages PAT" in a comment; meanwhile Phase 2 still showed a bare `plan && apply` loop (anti-doctrine), a stale user-supplied `ssh_public_key`, and Phases 3–5 marked 🔜 despite live validation | BOOTSTRAP.md rewritten in-run: token-minting how-to (classic `read:packages` for ghcr; Docker Hub read-only; fine-grained Contents+Metadata as the repo-READ shape), Phase 2 → saved-plan + driver path, stale key prereq dropped, phases flipped ✅ with ENV=prod deltas (SSM port-forward API, NLB URL checkpoint) | **DONE** — BOOTSTRAP.md; final pass re-reads it whole |

*(append rows as the run proceeds)*

| 6 | `cluster` phase | `no ansible_inventory output from …/terraform/environments/dev/50-compute` — phase hardcoded the dev layer + `inventory/dev.yml`, and `setup_kubeconfig` would next have resolved a dev/public endpoint | Anticipated frictions #2 + #3, confirmed verbatim | `platform.sh cluster()`: env-scoped generator arg + `inventory/${ENV}.yml` + explicit `-i`; prod branch installs the context at `--endpoint 127.0.0.1` and prints the SSM 6443 port-forward. `kubeconfig_setup.sh`: `ENV`-scoped compute dir + context name, private-IP fallback. shellcheck clean. Conductor gets the fix via commit → `ship_repo.sh` → `brzl-fetch` (the audited channel, not hand-edits) | LLM-CONDUCT; ACCESS.md prod-API section (final pass) |

| 7 | `cluster` phase — Ansible | All 3 nodes UNREACHABLE: `no such identity: ~/.ssh/brzl-dev-node` + `Permission denied (publickey)`. (NOT an SSM failure — the host-key exchange over the tunnel succeeded, proving agent + ProxyCommand fine on private nodes) | `ansible.cfg` `private_key_file` is dev-hardcoded; per-env data was living in static config instead of the generated inventory | `generate-inventory.sh` now emits a group var `ansible_ssh_private_key_file: ~/.ssh/<node-name-prefix>` derived from the TF output (brzl-prod-node-1 → brzl-prod-node), overriding the cfg default; cfg comment updated. Smoke-tested the derivation offline | LLM-CONDUCT; ACCESS.md if it names the key path (final pass) |

| 8 | (doc review during the Ansible run, user-spotted) | README Prerequisites contradicted the repo's own model | Two stale claims: "authenticated to a **scoped** profile with rights to create VPC/EC2/IAM/…" (Phase 0 runs as ADMIN — the scoped role doesn't exist yet, and a "scoped" profile that can create IAM is a contradiction) and "An SSH keypair (you supply the public key)" (both keypairs are TF-generated since 2026-06-02) | Prereqs rewritten: admin-for-Phase-0-only + scoped roles after; no key to supply; added the Session Manager plugin (genuinely required, was missing) | **DONE** — README; final pass re-reads Prereqs against BOOTSTRAP/ACCESS for drift |

| 9 | `gitops` phase | helm + kubectl all `127.0.0.1:6443 connection refused`; deploy-key placeholder warning; **phase reported success anyway** | (a) API tunnel (SSM port-forward) wasn't running — an operator-memory step, which the user rejected on principle; (b) deploy key is gitignored → never shipped, must be operator-staged (scp over SSM); (c) the emitted stream ends with `kubectl patch … \|\| true`, so the piped bash exits 0 and MASKS a failed bootstrap | **Fixed in-script, not in-place** (user directive): new sourceable `gitops/tools/api_tunnel.sh` (self-scoping — acts only when the kubeconfig server is `https://127.0.0.1:6443` and the port is dead; resolves the primary from the env's 50-compute, backgrounds the SSM forward with pid/log under /tmp, waits for the port); `platform.sh` `_kube_ready()` called by every kubectl phase (cluster/gitops/watch/roundtrip/operator/recover/verify); `gitops()` now asserts the ApplicationSet exists post-run. Deploy key scp'd from laptop over the SSM channel (stays operator-staged — it's a secret, correctly so) | LLM-CONDUCT; ACCESS.md prod-API section can now just say "the driver manages the tunnel; `api_tunnel.sh stop_api_tunnel` to drop it" |

| 10 | `watch` — demo-app stuck | demo-app `OutOfSync`/`Missing`, sync op "one or more synchronization tasks are not valid", retrying | demo-app's kustomization ships a **ServiceMonitor**, and the prod appset had **no monitoring** (an LLM scope cut the user didn't explicitly approve) → the `monitoring.coreos.com` CRD was absent, invalidating the sync task. The local k3d overlay had already hit + solved the identical problem (delete patch) | **User decision: add monitoring to prod properly** rather than patch around it: new `gitops/infrastructure/monitoring/values-prod.yaml` (dev values, `brzl-prod-*` prefixes, verified identical-modulo-prefix), monitoring element added to the prod appset (wave 1, hostParams), prometheus-community repo restored to the prod AppProject; interim ServiceMonitor delete patch reverted | LLM-CONDUCT (incl. the scope-cut lesson: a cut needs an explicit ask, not a buried note). ARCHITECTURE prod-ADR should name the values-prod prefix pattern |

| 11 | `watch` — monitoring app | admission-create job `InvalidImageName` | The prod templatePatch was authored core-only and **omitted the `hostParams` render loop** dev has; adding the monitoring element re-introduced a consumer of it, so `global.imageRegistry` kept the `__ECR_REGISTRY_HOST__` sentinel (underscores → invalid registry hostname). LLM authoring miss #2: a trimmed copy diverged from its source, then grew back the dependency | hostParams loop restored to the prod templatePatch (verbatim from dev) | LLM-CONDUCT. Final-pass thought: dev/prod appsets are 90% duplicated — a diff-review note (or future single-source generation) belongs in the prod ADR |

| 12 | forced re-syncs | monitoring `Running — waiting for completion of hook batch/Job/…admission-create` indefinitely; demo-app `Failed … (retried 5 times)`; sync patches produced "no motion" | (a) The hook Job had been hand-deleted while the sync op was mid-flight → the op waits forever on a ghost; a new `.operation` can't start while one exists. (b) demo-app had exhausted its retry budget on the absent CRD | Terminate the wedged op (`--type json` remove `/operation`) → fresh sync recreates the hook Job with the now-valid image → CRDs land → demo-app force-synced | RECOVERY.md ArgoCD section: add "terminate-then-resync" for wedged hook ops (never hand-delete a hook mid-sync); pairs with the existing retry-budget note |
| 13 | (design, user question) | "How is a hand-applied ApplicationSet valid GitOps?" | It isn't, fully — the appset sits above the imperative bootstrap line; changes to it are out-of-band kubectl applies (felt 3× today, one missed). Same property in dev, never felt | **Decision (user): document, don't build today.** The fix is the standard root-app pattern: a wave -1 cluster-config Application syncing `gitops/clusters/<env>/` with an `include` glob for `applicationset.yaml`+`project.yaml` ONLY — `in-cluster.yaml` must stay excluded (its live host/bucket annotations are deliberately not in git; self-heal would strip them, ADR-0016) | ARCHITECTURE prod ADR: known limitation + the designed fix, post-delivery build |

## Anticipated friction — confirm or strike as the run reaches each

- [x] **STRUCK** — `write_arns_to_tfvars` dev-path worry didn't bite: all four
      `brzl-prod-*` pull-through rules confirmed live (the secrets/layers run
      handled the prod tfvars). Wave-1 first pulls showed the normal cold-cache
      import race (ErrImagePull for <3 min, kubelet backoff retries through it).
- [x] **CONFIRMED (row 6)** `generate-inventory.sh` dev default — `platform.sh`
      didn't pass the env layer; fixed at source.
- [x] **CONFIRMED (row 6)** `kubeconfig_setup.sh` dev compute dir + `public_ips`
      — env-scoped + private fallback + tunnel endpoint; fixed at source.
- [ ] demo-app image push needs `DEMO_APP_REPO=brzl-prod/demo-app` (env-var
      override exists in `build_push.sh`; does the driver's `images` phase set it?).
- [ ] `platform.sh` `operator()` phase: comment claims it installs EBS CSI + gp3,
      body doesn't (A2 follow-up #2, half-folded) — N/A for the GitOps `bootstrap`
      path (wave 0 covers storage) but still open for the standalone DR path.
- [ ] Conductor → private kube-API reachability: conductor lives in its own VPC,
      so post-Ansible kubectl phases need the SSM port-forward (server
      `https://127.0.0.1:6443` — in k3s default TLS SANs) rather than a node IP.

## Process note — phase resumption after a mid-`bootstrap` failure

When `bootstrap` stopped at 50-compute, recovery switched to running phases
individually — and the navigator's resume sequence skipped `images` (caught by
the user before the gitops phase would have failed on a missing demo-app image).
The canonical order is `secrets → layers → images → cluster → gitops → watch →
roundtrip`. **Hardening follow-up:** the driver could print "next phase: X" on
any phase failure (it knows the sequence), so a manual resume can't drop a step.

## Doc destinations checklist (final refinement pass)

- [ ] TEARDOWN.md — digest-row sweep ✅ (done in-run)
- [ ] ACCESS.md — prod kube-API access = SSM port-forward procedure
- [ ] BOOTSTRAP.md — prod-env deltas (backend.hcl, ENV=prod, NLB verify step)
- [ ] ARCHITECTURE.md — ADR for the prod placement model + Terraform-NLB choice
      (no cloud-controller ⇒ Service LoadBalancer pends; NLB→NodePort, SG-gated)
- [ ] README — prod placement note ✅ (done in-run) + command block ✅
- [ ] LLM-CONDUCT.md — 2026-06-10 session entry (this whole day)
- [ ] LEADERSHIP.md §2 — "prod flips to private subnets" claim is now *built*,
      not just asserted — cite the prod env
