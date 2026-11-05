# barzel-cluster Platform

A platform that makes and operates Kubernetes clusters on different
substrates. It moves workloads through a chain of environments, from a laptop
to a public cloud.

## Language

### Where things run

**Kiesei**:
The container image that holds the full operator toolchain. Only a container
engine is necessary to operate it. It runs in one of two loci, as the driver
or the conductor.
_Avoid_: toolbox, ops image, tools container, kisei (spelling)

**Locus**:
The position where an operation occurs: the driver or the conductor.
_Avoid_: local (for this meaning), host, runner

**Driver**:
The kiesei locus external to the cluster. It makes the cluster, puts phases in
sequence, and sends commands to the conductor. It is the only locus that can
remove or replace a cluster. Accurate name: kiesei nahag.
_Avoid_: orchestrator, seed locus, laptop (for this meaning)

**Conductor**:
The kiesei locus in the cluster. It operates the commands that the driver sends
to it. A conductor must not operate a phase that removes or replaces its own
cluster. Accurate name: kiesei bakar.
_Avoid_: bastion, jump host, conductor instance

**Substrate**:
The thing that a cluster operates on: `local` (this machine, with k3d),
`aws`, `gcp`, or DigitalOcean. Each cloud provider is a separate substrate.
The control plane on it (k3d, EKS, GKE) is not the substrate. Accurate name:
hatzer.
_Avoid_: platform, provider, cloud (for this meaning), k3d (for this meaning)

**Substrate adapter**:
The set of steps that make, change, or remove the cluster on one substrate.
Each substrate has one adapter, and all adapters have the same interface.
_Avoid_: backend, plugin

### What moves through the chain

**Environment**:
One step of the promotion chain: `dev`, `test`, `stage` or `production`.
Each environment has its own configuration and its own deployed resources.
The dev environment is the first step. It runs on the local substrate.
_Avoid_: local (for this meaning), workspace, cluster (for this meaning)

**Promotion chain**:
The sequence of environments that a change must go through, from dev to
production.
_Avoid_: pipeline, release train

**Workload**:
A software application that the platform operates on a cluster. The
platform does not depend on any workload.
_Avoid_: app, service (for this meaning)

**Example app**:
The workload that shows what the platform can run: a stateless web service
with a stateful database. Any other workload can take its place. It is also
the workload that the bring-up checks.
_Avoid_: demo, test app, smoke workload

**Follow policy**:
How an environment follows a workload. `release`: the release tag the
platform names for it. `branch`: the newest commit of the workload's
development branch, and the image its CI published for that commit.
_Avoid_: tracking mode, image policy, update strategy

**Environment definition**:
The one file, `env/<env>.env`, that tells all values for one environment.
Each value is a default that the operator can replace for a single test.
_Avoid_: config, profile, tfvars (for this meaning)

### How a change is applied

**Phase**:
One step of a bring-up, a recovery, or a teardown. A phase makes the commands
for its step but does not operate them.
_Avoid_: stage, task

**GitOps mode**:
The usual mode of an environment. Argo CD makes the cluster agree with a
pushed git branch.
_Avoid_: normal mode, sync mode

**Driver command**:
One instruction to the driver: `BRZL_ENV=<env> driver.sh <mode> <verb>`.
The mode is `cluster` (the usual mode: the operator makes, reads and
removes the cluster, and Argo CD runs it), `break-glass` or `audit`. The
verb is an action: `bootstrap`, `teardown`, `open`, `close`, `apply`. A
teardown runs nothing until the operator strips its guard in the pipe.
_Avoid_: subcommand, action (for the mode), up, down, next

**Sync switch**:
The one switch of an environment that stops or starts Argo CD's automated
sync for every Application. Only break-glass mode moves it, with a record.
_Avoid_: fast mode, dev mode, auto-sync flag, sync off, sync on

**Break-glass mode**:
A mode of any environment for an emergency, and for a local test of the
working tree. Argo CD pauses and does not sync, and the admins get full
rights while it is open, each under their own name. Each use is recorded
and reviewed afterwards. Its verbs are `open`, `apply` (local) and `close`.
_Avoid_: fast mode, intervention mode, emergency mode, hold, release, pause,
resume

**Audit mode**:
The driver mode that starts and stops the reader of the admin log store:
`audit bootstrap`, `audit teardown`. It needs no cluster.
_Avoid_: readonly, reader mode

**Run sheet**:
The file of commands that one phase emitted for one environment. The driver
records it before it runs it, and keeps it afterwards, so it is the exact
record of what ran. The conductor runs the run sheets that the driver sends.
Accurate name: seder (an ordered sequence that is followed).
_Avoid_: run-log (retired 2026-10-14), script, procedure (for this meaning),
transcript, history

**Run output**:
The recorded output of a run sheet as it ran, kept beside the run sheet with
its exit status. The admin log store receives it.
_Avoid_: run-log, log, transcript

### Access

**Admin portal**:
The landing page of an environment, over HTTPS. It links to every service in
the cluster and gives the matching CLI commands. Sign-on leads to it.
_Avoid_: dashboard, homepage, launcher

**TLS type**:
Where an environment's certificates come from: `letsencrypt` (a public CA;
the environment has a public name) or `local-ca` (the cluster secret store
is the CA; nothing public is needed). Each environment has one.
_Avoid_: cert mode, issuer (for this meaning)

**Local stand-in**:
A small service beside a local cluster that takes the place of a public
service the cloud would provide: the registry, the secret store, DNS, a CA.
A local environment needs nothing public, and keeps the shape of a
production environment.
_Avoid_: mock, fake, shim

### Logs

**Workload logs**:
The logs that the workloads write. Their readers are the people who develop
the workloads.
_Avoid_: app logs, application logs

**Platform logs**:
The logs of everything that is not a workload: Kubernetes, the platform
applications, the driver and the conductor. Their readers are the operators
and the auditors.
_Avoid_: system logs, infrastructure logs, cluster logs

**Admin log store**:
The log store for operation and audit. It keeps the bootstrap, control-plane
and access records of an environment. It is external to the cluster and
outlives it.
_Avoid_: external log store, audit store, central logging

**Reader of the admin log store**:
A Grafana and a Loki on the operator's machine that only read the admin log
store, when the cluster's own Grafana cannot. It needs no cluster, and it has
no sign-on: only the operator's machine can reach it. Audit mode starts
and stops it.
_Avoid_: emergency Grafana, offline Grafana, log viewer, reader_on

**Diagnostic log store**:
The log store for detailed logs, from workloads and from the platform
applications, that operators read to find a fault. It is lost with the
cluster unless its logs are also sent to another store.
_Avoid_: cluster log store, workload log store, debug store

**Cold log store**:
The log store for records that must outlive the other stores. It keeps a
copy of each admin record, and the logs of each namespace that asks for it.
It is external to the cluster, and nothing removes its records.
_Avoid_: archive, backup, cold storage (for the store)

### Secrets

**Bootstrap secret source**:
A source of secrets that the driver reads before the cluster is available. Each
source gives its values to the driver as environment variables.
_Avoid_: secret store (for this meaning), vault

**Cluster secret store**:
The secret store that the cluster and its workloads read through the External
Secrets Operator. Each substrate selects the store. The store is external to
the cluster, exists before it, and outlives it.
_Avoid_: vault (for this meaning), secret backend

**Secret-store adapter**:
The steps that write one secret into one type of cluster secret store.
_Avoid_: secret driver, provider

### Roles

"Role" alone is ambiguous in this platform. It has five meanings, and each
one has its own name below. Always use that name. A store policy is not a
role, but an auth role names one, so it is in this list too.

**PKI role**:
A rule in the cluster secret store's certificate authority. It limits which
certificates the store signs: the names, the use (server or client) and the
longest life. Two exist. `portal` signs server certificates for the
environment's host name and the names under it: the admin portal and the
log intake. `log-shipper` signs client certificates for the collector
beside the cluster, and nothing else.
_Avoid_: issuer (that is cert-manager's object that asks for a signature),
certificate profile

**Auth role**:
A rule in the cluster secret store that lets one Kubernetes service account
log in, and names the store policies that it then has. Two exist. `eso`
lets External Secrets read secrets (policy `eso-reader`). `cert-manager`
lets cert-manager ask the `portal` PKI role for a signature (policy
`pki-issuer`).
_Avoid_: binding, login role

**Store policy**:
The paths in the cluster secret store that a token may read or write.
Three exist: `driver` (the operator's work through the driver), `eso-reader`
and `pki-issuer`.
_Avoid_: policy (alone: a follow policy is a different thing), ACL

**Kubernetes role**:
What a service account may do with the cluster's objects: a Kubernetes Role
or ClusterRole. The platform's own: the conductor has `cluster-admin`, the
in-cluster collector reads pods, namespaces, nodes and events, and the
store's token reviewer has `system:auth-delegator`.
_Avoid_: permissions, RBAC (for one role)

**Cloud role**:
An identity in a cloud provider that CI, a node or a person takes on, with
short-lived credentials. On AWS: `<prefix>-tofu-plan` and
`<prefix>-tofu-apply` (CI, through GitHub's OIDC provider) and the role of
each node.
_Avoid_: IAM user, account

**Access tier**:
A group of people that sign-on lets through, with the same access in each
service. Three exist: `admins` (all access), `operators` (operate the
platform, but not administer it) and `auditors` (read everything, change
nothing). Membership is a
team in the GitHub organization.
_Avoid_: role tier, group (for this meaning)
