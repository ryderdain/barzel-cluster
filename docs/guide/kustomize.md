# Kustomize — a guide for this repo

*Draft (2026-10-15). Part of the guidebook: one file for each tool that
barzel-cluster uses. The documentation run after the last passes completes
it.*

## What Kustomize is

Kustomize makes Kubernetes manifests for one environment from plain YAML
files and a list of changes. It has no templates: every input file is valid
Kubernetes YAML that you can read and apply as it is. A change is written as
a patch or as a transformer (for example "use this image tag"), not as a
placeholder in the file.

Kustomize is part of `kubectl`. Two commands are sufficient to start:

```sh
kubectl kustomize <dir>        # print the result (changes nothing)
kubectl apply -k <dir>         # apply the result to the cluster
```

Argo CD also has Kustomize inside it. When an Application points at a
directory that has a `kustomization.yaml` file, Argo CD renders it and
applies the result.

## The basics

**The `kustomization.yaml` file.** Each Kustomize directory has one. It
names the inputs and the changes:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:          # the inputs: files, or other Kustomize directories
  - deployment.yaml
  - service.yaml
images:             # change an image name or tag, wherever it occurs
  - name: example/app
    newTag: "1.2.3"
patches:            # change one object
  - target: {kind: Deployment, name: app}
    patch: |-
      - op: replace
        path: /spec/replicas
        value: 1
```

**Base and overlay.** A *base* is a directory with the manifests that every
environment shares. An *overlay* is a directory that names the base as a
resource and adds the changes for one environment. The base does not know
about its overlays.

```text
 base/                         overlay/ (one environment)
 ┌─────────────────────┐       ┌──────────────────────────────┐
 │ kustomization.yaml  │◀──────│ kustomization.yaml           │
 │ deployment.yaml     │ uses  │   resources: [../base]       │
 │ service.yaml        │       │   patches:   [replicas = 1]  │
 └─────────────────────┘       └──────────────┬───────────────┘
                                              │ kubectl kustomize overlay/
                                              ▼
                               the manifests for that environment
```

**Patches.** Kustomize has two types of patch:

- A *JSON patch* (RFC 6902) is a list of operations: `add`, `replace`,
  `remove`, each at a path in the object. Use it to change one field.
- A *strategic merge patch* is a part of the object, written as YAML. Its
  fields are merged into the object. The special line `$patch: delete`
  removes the whole object from the result.

**Transformers.** Some changes apply to many objects at once: `images`
(image name and tag), `namespace` (one namespace for all objects), and
`labels`.

**Generators.** `configMapGenerator` and `secretGenerator` make a ConfigMap
or a Secret from files. Kustomize adds a hash of the content to the name, and
updates each reference to it. When a file changes, the name changes, and the
Deployment that uses it starts new pods. You do not need to restart them.

## How it is used here

The manifests are in two layers: the **bases** describe a component for all
environments, and the **overlays** change it for one environment. The
platform's overlays are in `gitops/clusters/<env>/`. A workload keeps its
own bases and overlays in its own repo (ADR-0034): the example app,
[chofesh](https://github.com/tzvat/chofesh), has `deploy/base`,
`deploy/local` and `deploy/aws`.

```text
 this repo
 gitops/infrastructure/portal/      base: the admin portal (nginx, Service,
                                    Certificate, configMapGenerator)
        ▲
        │ resources: ../../../infrastructure/portal
 gitops/clusters/local/portal/      overlay: the Service becomes a NodePort
 gitops/clusters/<env>/pki/         no base: the TLS type's issuer (ADR-0036)
 gitops/clusters/<env>/secret-store/  no base: the store definition of each
                                    environment (ADR-0026)

 the example app's repo (chofesh)
 deploy/base/                       Deployment, Service, the CNPG Cluster `pg`
 deploy/local/                      overlay: 1 Postgres instance
 deploy/aws/                        overlay: 3 instances, gp3, S3 backups,
                                    metrics, the Grafana dashboard
```

**Argo CD does the rendering, not the driver.** The platform ApplicationSet
(`gitops/platform/applicationset.yaml`, ADR-0025) makes one Application for
each element. A `kustomize` element points at a directory in this repo, or,
for a workload, in the repo the element names (`repo`, `revision`). On
local, it is the local overlay (`localPath`). On other environments, it is
the base or the cloud overlay. Values that differ for each environment are
not in git. They come from the cluster's
registration (its cluster Secret), and the ApplicationSet adds them to the
Application as Kustomize settings when it renders it:

```text
 cluster Secret (written by phase 30)       git (this repo, or the workload's)
 annotations: registry host, prefixes;      base + overlay directories
 label: the follow policy                   (+ the branch head, from GitHub)
        │                                            │
        ▼                                            ▼
 ApplicationSet ──renders──▶ Application ──Kustomize──▶ manifests ──▶ cluster
                             kustomize:
                               images:  [ghcr.io/tzvat/chofesh → <registry host>/…:<tag>]
                               patches: [pg image → <registry host>/…]
```

So the files in git name images as published (`ghcr.io/tzvat/chofesh`,
`ghcr.io/cloudnative-pg/postgresql`), and the Application replaces each
registry host with the registry of that environment. No account ID or host
name goes into git, and the workload's manifests know nothing of the
platform's registry. A tag is the workload's. An environment that follows
the development branch gets the commit's tag from the SCM generator. One
that follows a release gets the tag the manifests name (ADR-0034).

**The admin portal (pass 5c)** is a Kustomize directory,
`gitops/infrastructure/portal/`: a Deployment of nginx, a Service, a
Certificate, and a `configMapGenerator` that makes the ConfigMap from
`nginx.conf` and `index.html`. A change to the page starts new nginx pods
by itself. The local overlay, `gitops/clusters/local/portal/`, only makes
the Service a NodePort; the ApplicationSet patches the certificate's host
name in from the cluster's registration.

## Try it

```sh
# The example app's local overlay (its checkout beside this repo): one instance
kubectl kustomize ../chofesh/deploy/local

# Compare with the base, and with the cloud overlay
kubectl kustomize ../chofesh/deploy/base
kubectl kustomize ../chofesh/deploy/aws
```

## Where to read more

- The Kustomize reference: <https://kubectl.docs.kubernetes.io/references/kustomize/>
- Argo CD and Kustomize: <https://argo-cd.readthedocs.io/en/stable/user-guide/kustomize/>
