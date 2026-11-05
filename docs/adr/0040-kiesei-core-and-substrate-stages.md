# ADR-0040 — The kiesei image: a core stage and one stage per substrate

## Status

Accepted (BACKLOG item 39, the user's request) · **Date:** 2026-11-05 ·
**Extends:** ADR-0021 (kiesei, the driver and the conductor), ADR-0030 (the
substrate adapter interface), ADR-0039 (the substrate names)

## Context

The kiesei image held every tool of the take-home in one stage: the AWS
tools, the Terraform tools, Ansible, trivy, the CNPG plugin, and the
platform tools. Unpacked, it was 2.1 GB. The user asked whether a
multi-stage build would shrink it. It would not: each install block
removes its download in its own layer, so the size is the tools. Half of
them serve the AWS path, which is frozen (BACKLOG 10), and the driver
calls none of trivy, tflint or kubectl-cnpg.

## Decision

- **One Dockerfile, three stages.** `core` holds the platform tools every
  substrate needs: kubectl, helm, kustomize, argocd, kubelogin, yq, git, jq,
  the docker CLI, psql, tmux, vim and less. `aws` is `core` plus aws-cli,
  the session-manager plugin, tofu, tflint and ansible. `local` is `core`
  plus k3d. `local` is the last stage, so it is the default target.
- **The tag names the substrate**, as `BRZL_SUBSTRATE` and
  `BRZL_KIESEI_IMAGE` do: `kiesei:local`, `kiesei:aws`. The command in the
  documents, `docker build -t kiesei:local containers/kiesei`, does not
  change.
- **tmux and vim stay in core** (the user). tmux keeps a session alive
  through a dropped connection during a long operation at a remote locus.
  vim serves the kiesei shell.
- **trivy and kubectl-cnpg are parked.** Nothing in the driver calls them.
  Their verified install blocks are in git history, and a later stage can
  take them back.
- **Each install block is unchanged.** The stages move the blocks. The
  pins and the checksum and signature checks are the same.

## Consequences

- The local image loses about 1 GB unpacked: the AWS stage's tools and the
  two parked ones.
- A substrate adapter can get its own stage with its own tools (ADR-0030).
  The AWS stage is not built until the AWS path returns.
- The `ARG` pins are global, before the first `FROM`. Each stage names the
  ones it uses, because a stage does not inherit another stage's `ARG`.
- The two GPG keys in the build context serve the `aws` stage only.
