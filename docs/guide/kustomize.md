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
environments, and the **overlays** in `gitops/clusters/<env>/` change it for
one environment.

```text
 gitops/operators/postgres/         base: the CNPG Cluster `pg` (3 instances,
                                    backups, monitoring), as on AWS
 gitops/applications/demo-app/      base: the demo-app's Deployment, Service,
                                    secret projection, ServiceMonitor
        ▲                     ▲
        │ resources: ../../.. │
 gitops/clusters/local/postgres/    overlay: 1 instance, the `local-path`
                                    storage class, no backup, no monitoring
 gitops/clusters/local/demo-app/    overlay: removes the ServiceMonitor
                                    (local has no metrics stack yet)
 gitops/clusters/<env>/secret-store/  no base: the store definition of each
                                    environment (ADR-0026)
```

**Argo CD does the rendering, not the driver.** The platform ApplicationSet
(`gitops/platform/applicationset.yaml`, ADR-0025) makes one Application for
each element. A `kustomize` element points at a directory. On local, it is
the overlay (`localPath`). On other environments, it is the base. Values that
differ for each environment are not in git. They come from the cluster's
registration (its cluster Secret), and the ApplicationSet adds them to the
Application as Kustomize settings when it renders it:

```text
 cluster Secret (written by phase 30)       git (this repo)
 annotations: registry host, prefixes,      base + overlay directories
 demo-app image tag                                  │
        │                                            │
        ▼                                            ▼
 ApplicationSet ──renders──▶ Application ──Kustomize──▶ manifests ──▶ cluster
                             kustomize:
                               images:  [demo-app → <registry host>/…:<tag>]
                               patches: [pg image → <registry host>/…]
```

So the files in git name images with a sentinel
(`__ECR_REGISTRY_HOST__/brzl-dev/demo-app`), and the Application replaces it
with the registry of that environment. No account ID or host name goes into
git.

**One older use.** `gitops/clusters/local/kustomization.yaml` combines the
whole local stack into one directory. Only the legacy SSO bring-up
(`gitops/clusters/local/k3d-up.sh --with-sso`) uses it. The driver does not.

**Next use (pass 5c).** The admin portal is a Kustomize directory: a
Deployment of nginx, a Service, and a `configMapGenerator` that makes the
ConfigMap from `nginx.conf` and `index.html`. A change to the page then
starts new nginx pods by itself.

## Try it

```sh
# The local postgres overlay: one instance, local-path, no ScheduledBackup
kubectl kustomize gitops/clusters/local/postgres

# Compare with the base
kubectl kustomize gitops/operators/postgres
```

## Where to read more

- The Kustomize reference: <https://kubectl.docs.kubernetes.io/references/kustomize/>
- Argo CD and Kustomize: <https://argo-cd.readthedocs.io/en/stable/user-guide/kustomize/>
