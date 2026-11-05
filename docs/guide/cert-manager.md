# cert-manager — a guide for this repo

*Draft (2026-10-15). Part of the guidebook: one file for each tool that
barzel-cluster uses. The documentation run after the last passes completes
it.*

## What cert-manager is

cert-manager is a Kubernetes operator that gets TLS certificates from a
certificate authority (CA) and keeps them renewed. You describe the
certificate you want in a `Certificate` object. cert-manager asks a CA for
it and writes the result into a Kubernetes `Secret`. Before the certificate
expires, it asks again. The program that uses the certificate (here, nginx)
only reads the Secret.

It runs as three small pods: the controller (does the work), the webhook
(validates the objects) and the cainjector (helps other webhooks trust each
other). It adds its own object types (CRDs) to the cluster.

## The basics

**Issuers.** An `Issuer` or `ClusterIssuer` object says *which CA* to ask and
*how*. The type of issuer is named after the kind of CA it talks to:

| Issuer type | Talks to | Used here |
| --- | --- | --- |
| `acme` | Let's Encrypt, or any ACME server | `letsencrypt` mode (pass 8) |
| `vault` | A Vault PKI engine. OpenBao has the same API, so this is how cert-manager talks to OpenBao | `local-ca` mode |
| `ca` | A CA key that is kept in a Kubernetes Secret | — |
| `selfSigned` | No CA: the certificate signs itself | — |

A `ClusterIssuer` is cluster-wide, and an `Issuer` belongs to one namespace. A
`ClusterIssuer` reads its own secrets and service accounts from
cert-manager's namespace.

**Certificates.** A `Certificate` object names the host names, how long the
certificate lasts, when to renew it, and the issuer to ask:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: portal
spec:
  secretName: portal-tls          # the Secret cert-manager writes
  dnsNames: [local.barzel.sh]
  duration: 2160h                 # 90 days
  renewBefore: 720h               # renew 30 days before the end
  issuerRef: {name: brzl-portal, kind: ClusterIssuer}
```

cert-manager makes a private key, sends a certificate signing request to
the issuer, and writes `tls.crt` and `tls.key` into the Secret. When the
renewal time comes, it does the same again and replaces the Secret's
content. A pod that mounts the Secret sees the new files a short time later.

**How it proves the host name.** A public CA (ACME) must check that you own
the name. With *DNS-01*, cert-manager writes a TXT record into the public
DNS zone, and the CA reads it. The host itself need not be reachable from
the internet. With *HTTP-01*, the CA connects to the host on port 80. A
private CA (the `vault` type) checks nothing: its role says which names it
may sign.

```text
 Certificate ──▶ cert-manager ──CSR──▶ issuer ──▶ CA
                      │                            │
                      │◀────── signed certificate ──┘
                      ▼
 Secret portal-tls (tls.crt, tls.key) ──mounted──▶ nginx
```

## How it is used here

cert-manager is an element of the platform ApplicationSet, at the same wave
as ESO. It renews the admin portal's certificate (ADR-0028, ADR-0036).

- **The `Certificate` is in the portal's base**,
  `gitops/infrastructure/portal/certificate.yaml`. Its host name is a
  placeholder. The ApplicationSet replaces it with the cluster's
  `brzl.dev/portal-host` annotation, so the environment definition stays
  the one source of the name.
- **The issuer is the environment's TLS type**, in
  `gitops/clusters/<env>/pki/`. On local it is a `vault` issuer that points
  at OpenBao, outside the cluster. cert-manager logs in to OpenBao with a
  service-account token (Kubernetes auth), as ESO does. OpenBao lets that
  role do one thing: ask the `portal` role to sign.
- **Phase 25-bootstrap prepares OpenBao**: the PKI engine, a root CA made
  once, the `portal` role, and the auth role. The CA certificate is written
  to `var/secret-store/dev/ca.crt`, and the phase's check prints the one
  command that makes your machine trust it.
- **nginx picks up a renewed certificate by itself**: its certificate paths
  hold a variable, so it opens the files at each TLS handshake.

```text
 OpenBao (outside the cluster)            the cluster
 ┌──────────────────────────┐            ┌─────────────────────────────────┐
 │ pki/ engine: root CA     │◀──sign────│ cert-manager                     │
 │ role portal: may sign    │            │   ClusterIssuer brzl-portal (vault)
 │   local.barzel.sh        │            │   Certificate portal → Secret    │
 │ auth: role cert-manager  │◀──login───│   (token of brzl-pki-client)     │
 └──────────────────────────┘            │ nginx reads Secret portal-tls    │
         ▲ phase 25 makes these          └─────────────────────────────────┘
```

## Try it

```sh
export KUBECONFIG=var/run/dev/current/kubeconfig
kubectl -n portal get certificate portal        # READY True
kubectl -n portal describe certificate portal   # the events: issued, renewed
kubectl get clusterissuer brzl-portal           # READY True
# the certificate itself
kubectl -n portal get secret portal-tls -o jsonpath='{.data.tls\.crt}' \
  | base64 -d | openssl x509 -noout -subject -issuer -dates
```

## Where to read more

- The cert-manager documentation: <https://cert-manager.io/docs/>
- The Vault issuer (used for OpenBao):
  <https://cert-manager.io/docs/configuration/vault/>
