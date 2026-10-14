# ADR-0028 — The admin portal: one nginx, a static page, a path for each service

**Status:** Accepted (design; built in BACKLOG pass 5c) · **Date:**
2026-10-14 · **Supersedes in part:** ADR-0017 (UI access by port-forward),
ADR-0018 (the per-host edge with Traefik `IngressRoute`; its sign-on part
stays for pass 6a)

**Context.** Each service of the cluster needed its own port-forward: Argo
CD, the demo-app, and soon Grafana. That is hard to keep track of. The
legacy SSO edge (`gitops/clusters/local/sso/`) uses Traefik's own routing
objects, which SPEC §3 lists as a portability violation. The user asked for
the simplest page that serves the purpose, on the model of mdoc.su: "even a
well-formed nginx.conf should be able to serve it". HTTPS is there to
encrypt the traffic, not to prove the page to the user.

**Decision.**

- **One nginx in the cluster is both the page and the way in.** It serves a
  static `index.html` and passes each path to its service: `/argocd/`,
  `/grafana/`, `/apps/<workload>/`. Each app gets the setting for its
  sub-path. The links in the page are relative, so the same file works in
  every environment without templating (Q113).
- **One host name and one certificate** for each environment. The same URL
  serves the CLI tools that speak HTTP (`curl`, the Argo CD CLI with
  `--grpc-web-root-path`). `kubectl` and `bao` keep their own endpoints.
- **The page also lists the CLI commands** for each service.
- **On local, no port-forward:** a fixed node port is mapped to a host port
  when the cluster is made.
- **Two TLS modes, in the environment definition** (Q114):
  - `letsencrypt`, the default: an owned domain (for example
    `local.barzel.sh`) with a DNS record to `127.0.0.1`. The browser trusts
    the certificate. Let's Encrypt allows 5 identical certificates a week,
    so the certificate is kept in the secret store and outlives the cluster.
  - `local-ca`: any domain the operator chooses. The CA is OpenBao's PKI
    engine, outside the cluster. A `*.localhost` name needs no setup; any
    other name needs one hosts-file line, which the driver prints. The
    browser warns until the operator trusts the CA, which is acceptable.
- **Sign-on comes later and leads to the portal** (pass 6a, nginx
  `auth_request`). The portal also works without it.

**Consequences.**

- One place to start for every service, the same on every substrate.
- On a cloud, only the way to reach nginx changes; pass 8 decides it, with
  the Gateway API (ingress-nginx was retired in March 2026).
- Each new service needs one nginx location, one link in the page, and its
  sub-path setting.
- *Alternatives considered.* A host name for each service behind a Gateway:
  wildcard DNS and certificates, and a page filled in for each environment.
  Homepage (a dashboard product that finds services by annotation): more to
  run and less control over the CLI instructions.
