# ADR-0036 — cert-manager renews certificates; local stand-ins for DNS and a CA

## Status

Accepted · **Date:** 2026-10-15 (pass 5c, Q128 and Q130–Q137) · **Amends:**
ADR-0028 (the certificate flow and the default TLS mode)

## Context

ADR-0028 gave the admin portal one host name and one certificate, in one
of two TLS modes, and left the certificate flow open. The first design
(Q128) had the driver get the certificate in phase 25 and renew it only when
that phase ran again. That suits a local cluster that is remade often, and
nothing else: an environment on a cloud stands for months, and its workloads
will need renewed certificates too.

A second gap showed in the same round (user, Q134). A person must be able
to try barzel-cluster on their own machine. They must not need a public DNS
zone or a credential at a DNS provider. At the same time the local
environment must stand in for a production environment with public
endpoints. Then the platform is built against the same shape everywhere.
The two goals pull in different directions. The laptop substrate alone must
resolve them, with services that stand in for the public ones consistently.

## Decision

- **cert-manager is a platform component on every substrate.** It is an
  element of the platform ApplicationSet (wave 1, like ESO). The portal's
  `Certificate` object is in the portal's base. cert-manager writes the TLS
  Secret and renews it at two thirds of its 90-day lifetime. Renewal needs
  no driver run.
- **The TLS mode of an environment is a `ClusterIssuer` in
  `gitops/clusters/<env>/pki/`** (the `pki` element, wave 2). Only the issuer
  differs between modes, and the `Certificate` is the same:
  - `local-ca`: an issuer of type *vault*, because OpenBao has Vault's API.
    It points at the PKI engine of the cluster secret store, outside the
    cluster. Phase 25 makes the engine and a root CA, once (the CA outlives
    the cluster). It also makes a role that signs the portal's host, and the
    auth role that cert-manager logs in with (Kubernetes auth, as ESO). The
    CA key never leaves the store. The driver prints the one command that
    makes the machine trust the CA. The check warns until it is done.
  - `letsencrypt`: an issuer of type *ACME* with DNS-01. Pass 8 builds it
    with the cloud substrates.
- **The default mode depends on the kind of substrate** (changes
  ADR-0028): `local-ca` for a local environment, `letsencrypt` on a cloud.
  The certificate is no longer copied into the secret store: the copy served
  only Let's Encrypt's limit on repeated certificates, and an OpenBao CA has
  no such limit. Pass 8 decides whether a cloud needs the copy.
- **nginx reads the certificate at each TLS handshake**, because its
  certificate paths hold a variable. A renewed Secret is served without a
  reload, a sidecar or a reloader.
- **A `.localhost` name by default, a DNS stand-in for a chosen name**
  (Q140). The default host of a local environment is `brzl-<env>.localhost`:
  macOS and browsers resolve every `*.localhost` name to `127.0.0.1` with
  no step at all, and `kiesei.sh` maps the name itself (`--add-host`). A
  casual test needs nothing. When the operator chooses another name, as if
  it were public (`local.barzel.sh`, `local.example.com`), the k3d adapter
  runs one small CoreDNS container beside Zot and OpenBao. It
  answers for the portal's host name only, with `127.0.0.1`, and the
  operating system is told to ask it for that name alone (macOS
  `/etc/resolver/<host>`, a line the driver prints). It has no link to the
  CoreDNS inside the cluster: it stands in for the public record, as OpenBao
  stands in for the cloud's secret store.
- **The host name is a value, not a pattern** (Q137). `BRZL_PORTAL_HOST` in
  the environment definition holds the full name, and no code builds it. The
  convention for a chosen domain is `<env>.<domain>` (for example
  `local.barzel.sh`), and an environment on a second machine takes the host
  into the environment's name (`local-huginn`). Changing the name is cheap
  until sign-on (pass 6a) fixes it in the kube-API server's issuer URL. A
  flat name also suits password managers, which often fail on
  `sub.sub.domain.tld`.

## Consequences

- One more operator in the cluster (three small pods), and one more
  Helm chart repository the AppProject allows.
- A reader meets CoreDNS twice. The guide (`docs/guide/`) and the adapter's
  comments name the stand-in by its purpose, not by its program.
- An existing local store (made before this decision) has a driver token
  without the PKI capabilities. The check says so, and the fix is to purge
  the store and run again (docs/LOCAL.md). The deploy key is then given
  once more.
- `kubectl` and `bao` keep their own endpoints. Sign-on (ADR-0035) later
  gives them the same identity, not the same host.

## Considered options

- *The driver renews (Q130 a).* A `renew` command like fast mode. Rejected:
  it suits only a cluster that is remade often, and it does not help dev or
  prod.
- *A general `again <phase>`* (Q130 b). Parked in BACKLOG, in case a later
  pass needs it. Renewal does not.
- *tinydns + dnscache for the stand-in* (Q136). Viable, but the last
  release is from 2001, there is no official image, and the resolver file
  makes a cache pointless. CoreDNS has an official image and is maintained.
- *Records on the home router.* Nothing to run. But it works only on that
  network, and it gives one address per name, not `127.0.0.1` on each
  machine.

## Amendment (BACKLOG 4a, 2026-10-22)

- The store's CA is made in phase 10, before the cluster, as the store is.
  Phase 25 writes the PKI role `portal` and cert-manager's auth role.
- The PKI role `portal` signs server certificates only. Its names are the
  portal's host and the names under it: the admin portal and, from 4a,
  the log intake `log-intake.<host>`.
- A second PKI role, `log-shipper`, signs client certificates for that one
  name. Only the driver can ask it. GLOSSARY, "Roles", names each kind of
  role.

