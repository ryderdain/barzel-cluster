# barzel-cluster Platform

A platform that makes and operates Kubernetes clusters on different
substrates. It moves workloads through a chain of environments, from a laptop
to a public cloud.

## Language

### Where things run

**Kiesei**:
The container image that holds the full operator toolchain. It is necessary
to have only a container engine to operate it. Each locus is a kiesei in one
of two modes.
_Avoid_: toolbox, ops image, tools container, kisei (spelling)

**Locus**:
The position where an operation occurs: the driver or the conductor.
_Avoid_: local (for this meaning), host, runner

**Driver**:
The kiesei mode external to the cluster. It makes the cluster, puts phases in
sequence, and sends commands to the conductor. It is the only locus that can
remove or replace a cluster. Accurate name: kiesei nahag.
_Avoid_: orchestrator, seed locus, laptop (for this meaning)

**Conductor**:
The kiesei mode in the cluster. It operates the commands that the driver sends
to it. A conductor must not operate a phase that removes or replaces its own
cluster. Accurate name: kiesei bakar.
_Avoid_: bastion, jump host, conductor instance

**Substrate**:
The thing that a cluster operates on. Examples: k3d on a laptop, AWS, GCP, or
DigitalOcean.
_Avoid_: platform, provider, cloud (for this meaning)

**Substrate adapter**:
The set of steps that make, change, or remove the cluster on one substrate.
Each substrate has one adapter, and all adapters have the same interface.
_Avoid_: backend, plugin

### What moves through the chain

**Environment**:
One step of the promotion chain. Each environment has its own configuration
and its own deployed resources. The local environment is the first step.
_Avoid_: stage, workspace, cluster (for this meaning)

**Promotion chain**:
The sequence of environments that a change must go through, from local to prod.
_Avoid_: pipeline, release train

**Workload**:
A software application that the platform operates on a cluster. The barzel
container is the primary workload.
_Avoid_: app, service (for this meaning)

**Smoke workload**:
A small workload whose only task is to show that a cluster operates
correctly. The demo-app is the smoke workload.
_Avoid_: demo, test app

**Environment definition**:
The one shell script that tells all values for one environment. Each value is
a default that the operator can replace for a single test.
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

**Fast mode**:
A mode of the local environment for changes to the structure of the cluster.
The driver applies the working tree directly, and Argo CD does not sync.
_Avoid_: dev mode, inner loop, direct mode

**Run-log**:
The recorded commands of one phase in one environment, as they operated.
_Avoid_: transcript, history

### Secrets

**Bootstrap secret source**:
A source of secrets that the driver reads before the cluster is available. Each
source gives its values to the driver as environment variables.
_Avoid_: secret store (for this meaning), vault

**Cluster secret store**:
The secret store that the cluster and its workloads read through the External
Secrets Operator. Each substrate selects the store.
_Avoid_: vault (for this meaning), secret backend

**Secret-store adapter**:
The steps that write one secret into one type of cluster secret store.
_Avoid_: secret driver, provider
