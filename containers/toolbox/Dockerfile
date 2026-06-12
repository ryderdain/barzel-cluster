# syntax=docker/dockerfile:1.7
#
# brzl-demo operator/CI toolbox (SPEC §4.2).
# One pinned arm64/Graviton image carrying the whole deploy toolchain so the
# 3-person team and CI run the exact same versions, and long ops (bootstrap,
# upgrades) survive an operator's SSO/SSH session timing out. Runs three ways
# from the same artifact: a laptop container, the cloud-init bootstrap VM
# (../bootstrap-vm), or a k8s Job.
#
# Toolchain: tofu, ansible, kubectl, helm, kustomize, argocd, kubectl-cnpg,
# aws-cli, session-manager-plugin, yq, trivy, tflint, psql, git, jq, tmux — see
# the pinned ARGs below.
#
# Base: python:3.14-slim-trixie — CPython 3.14 on Debian 13 (trixie) slim.
# Both are pinned to long-lived series (Python 3.14 EoL ~Oct 2030; Debian 13
# LTS ~2030), so patch/security fixes flow within those series while the
# major.minor stays put well past this project's delivery. ansible-core 2.20
# needs Python >=3.12, which a system-Python trixie (3.13) would also satisfy,
# but the official python image gives us the 3.14 control node deliberately.
#
# Build (native on a Graviton/Apple-silicon host, or via buildx):
#   docker buildx build --platform linux/arm64 -t brzl-dev/toolbox:<tag> \
#     containers/toolbox
#
# Every third-party binary is verified at build time — checksums for
# tofu/kubectl/helm/kustomize/argocd/kubectl-cnpg/trivy/tflint/yq (publishers
# ship SHA files), GPG signatures for the aws-cli installer (AWSCLI_VERIFY) and
# the session-manager-plugin .deb (SMP_VERIFY).

FROM python:3.14-slim-trixie

# Pinned toolchain. Bump deliberately; the verification below fails the build if
# a version/asset doesn't match its published checksum or signature.
ARG TOFU_VERSION=1.12.1
ARG KUBECTL_VERSION=1.31.5
ARG HELM_VERSION=3.16.4
ARG AWSCLI_VERSION=2.34.58
ARG SMP_VERSION=1.2.814.0
ARG ANSIBLE_CORE_VERSION=2.20.6
# Galaxy collections (exact pins; bump deliberately like the binaries). The
# roles are ansible.builtin-only today — these are staged for the k8s work
# (kubernetes.core) and general utility. All require ansible-core >=2.17.
ARG COMMUNITY_GENERAL_VERSION=13.0.1
ARG ANSIBLE_POSIX_VERSION=2.2.0
ARG KUBERNETES_CORE_VERSION=6.4.0
ARG KUSTOMIZE_VERSION=5.8.1
ARG ARGOCD_VERSION=3.4.3
ARG CNPG_PLUGIN_VERSION=1.29.1
ARG YQ_VERSION=4.53.2
ARG TRIVY_VERSION=0.71.0
ARG TFLINT_VERSION=0.62.1
# arm64-only image (Graviton end-to-end). Overridable for a multi-arch build.
ARG TARGETARCH=arm64
# Verify the aws-cli installer's GPG signature (recommended). Requires
# awscli-public-key.asc in the build context. Set false only to unblock a build
# where you can't supply the key — not recommended.
ARG AWSCLI_VERIFY=true
# Verify the session-manager-plugin .deb's GPG signature (recommended). Requires
# session-manager-plugin-key.asc in the build context (AWS's plugin signing key,
# keyid 2C4D4AFF6F6757EE — a different key than the aws-cli one). Set false only
# to unblock a build where you can't supply the key — not recommended.
ARG SMP_VERIFY=true

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# Fail pipelines on the first error, not just the last command.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Base OS utilities. python3/pip/venv come from the base image, so they are not
# installed here. We pin the *tools* (below) rather than distro packages;
# leaving these unpinned lets the image pick up Debian security updates.
#   postgresql-client → psql against the demo CloudNativePG database
#   tmux              → detachable shells so long ops survive a dropped session
#   less, vim         → the pager/editor missing from the slim base
# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl git jq unzip gnupg openssh-client tar \
        postgresql-client tmux less vim \
    && rm -rf /var/lib/apt/lists/*

# All third-party fetch/verify/install happens from /tmp.
WORKDIR /tmp

# --- OpenTofu (verify against published SHA256SUMS) -------------------------
RUN set -eux; \
    f="tofu_${TOFU_VERSION}_linux_${TARGETARCH}.zip"; \
    base="https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}"; \
    curl -fsSLO "${base}/${f}"; \
    curl -fsSLo SHA256SUMS "${base}/tofu_${TOFU_VERSION}_SHA256SUMS"; \
    grep " ${f}\$" SHA256SUMS | sha256sum -c -; \
    unzip -q "${f}" tofu -d /usr/local/bin; \
    chmod +x /usr/local/bin/tofu; \
    rm -f "${f}" SHA256SUMS; \
    tofu version

# --- kubectl (verify against published .sha256) ----------------------------
RUN set -eux; \
    base="https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/${TARGETARCH}"; \
    curl -fsSLO "${base}/kubectl"; \
    curl -fsSLo kubectl.sha256 "${base}/kubectl.sha256"; \
    echo "$(cat kubectl.sha256)  kubectl" | sha256sum -c -; \
    install -m 0755 kubectl /usr/local/bin/kubectl; \
    rm -f kubectl kubectl.sha256; \
    kubectl version --client

# --- helm (verify against published .sha256sum) ----------------------------
RUN set -eux; \
    f="helm-v${HELM_VERSION}-linux-${TARGETARCH}.tar.gz"; \
    curl -fsSLO "https://get.helm.sh/${f}"; \
    curl -fsSLo "${f}.sha256sum" "https://get.helm.sh/${f}.sha256sum"; \
    sha256sum -c "${f}.sha256sum"; \
    tar -xzf "${f}" --strip-components=1 -C /usr/local/bin "linux-${TARGETARCH}/helm"; \
    rm -f "${f}" "${f}.sha256sum"; \
    helm version --short

# --- kustomize (verify against published checksums.txt) --------------------
RUN set -eux; \
    f="kustomize_v${KUSTOMIZE_VERSION}_linux_${TARGETARCH}.tar.gz"; \
    base="https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize/v${KUSTOMIZE_VERSION}"; \
    curl -fsSLO "${base}/${f}"; \
    curl -fsSLo checksums.txt "${base}/checksums.txt"; \
    grep " ${f}\$" checksums.txt | sha256sum -c -; \
    tar -xzf "${f}" -C /usr/local/bin kustomize; \
    rm -f "${f}" checksums.txt; \
    kustomize version

# --- argocd CLI (verify against published cli_checksums.txt) ----------------
RUN set -eux; \
    f="argocd-linux-${TARGETARCH}"; \
    base="https://github.com/argoproj/argo-cd/releases/download/v${ARGOCD_VERSION}"; \
    curl -fsSLO "${base}/${f}"; \
    curl -fsSLo cli_checksums.txt "${base}/cli_checksums.txt"; \
    grep " ${f}\$" cli_checksums.txt | sha256sum -c -; \
    install -m 0755 "${f}" /usr/local/bin/argocd; \
    rm -f "${f}" cli_checksums.txt; \
    argocd version --client

# --- kubectl-cnpg plugin (verify against published checksums.txt) -----------
RUN set -eux; \
    f="kubectl-cnpg_${CNPG_PLUGIN_VERSION}_linux_${TARGETARCH}.tar.gz"; \
    base="https://github.com/cloudnative-pg/cloudnative-pg/releases/download/v${CNPG_PLUGIN_VERSION}"; \
    curl -fsSLO "${base}/${f}"; \
    curl -fsSLo checksums.txt "${base}/cnpg-${CNPG_PLUGIN_VERSION}-checksums.txt"; \
    grep " ${f}\$" checksums.txt | sha256sum -c -; \
    tar -xzf "${f}" -C /usr/local/bin kubectl-cnpg; \
    rm -f "${f}" checksums.txt; \
    kubectl-cnpg version

# --- yq (mikefarah; verify via checksums + checksums_hashes_order) ----------
# yq ships one multi-algorithm `checksums` table; `checksums_hashes_order` names
# the columns. Find the SHA-256 column index, then verify the raw binary.
RUN set -eux; \
    f="yq_linux_${TARGETARCH}"; \
    base="https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}"; \
    curl -fsSLO "${base}/${f}"; \
    curl -fsSLo checksums "${base}/checksums"; \
    curl -fsSLo checksums_hashes_order "${base}/checksums_hashes_order"; \
    col=$(( $(grep -n '^SHA-256$' checksums_hashes_order | cut -d: -f1) + 1 )); \
    want=$(grep "^${f} " checksums | awk -v c="${col}" '{print $c}'); \
    echo "${want}  ${f}" | sha256sum -c -; \
    install -m 0755 "${f}" /usr/local/bin/yq; \
    rm -f "${f}" checksums checksums_hashes_order; \
    yq --version

# --- trivy (verify against published checksums.txt) ------------------------
# Asset arch label is capitalized (Linux-ARM64), unlike the others.
RUN set -eux; \
    f="trivy_${TRIVY_VERSION}_Linux-ARM64.tar.gz"; \
    base="https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}"; \
    curl -fsSLO "${base}/${f}"; \
    curl -fsSLo checksums.txt "${base}/trivy_${TRIVY_VERSION}_checksums.txt"; \
    grep " ${f}\$" checksums.txt | sha256sum -c -; \
    tar -xzf "${f}" -C /usr/local/bin trivy; \
    rm -f "${f}" checksums.txt; \
    trivy --version

# --- tflint (verify against published checksums.txt) -----------------------
RUN set -eux; \
    f="tflint_linux_${TARGETARCH}.zip"; \
    base="https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VERSION}"; \
    curl -fsSLO "${base}/${f}"; \
    curl -fsSLo checksums.txt "${base}/checksums.txt"; \
    grep " ${f}\$" checksums.txt | sha256sum -c -; \
    unzip -q "${f}" tflint -d /usr/local/bin; \
    chmod +x /usr/local/bin/tflint; \
    rm -f "${f}" checksums.txt; \
    tflint --version

# --- aws-cli v2 (GPG-verified installer) -----------------------------------
# Public key is COPYed from the build context so the verification is real and
# auditable. Obtain it from the AWS CLI docs ("Verifying the integrity ...").
COPY awscli-public-key.asc /tmp/awscli-public-key.asc
RUN set -eux; \
    curl -fsSLo awscliv2.zip \
      "https://awscli.amazonaws.com/awscli-exe-linux-aarch64-${AWSCLI_VERSION}.zip"; \
    if [ "${AWSCLI_VERIFY}" = "true" ]; then \
      curl -fsSLo awscliv2.zip.sig \
        "https://awscli.amazonaws.com/awscli-exe-linux-aarch64-${AWSCLI_VERSION}.zip.sig"; \
      gpg --import /tmp/awscli-public-key.asc; \
      gpg --verify awscliv2.zip.sig awscliv2.zip; \
    else \
      echo "WARNING: skipping aws-cli signature verification (AWSCLI_VERIFY=false)"; \
    fi; \
    unzip -q awscliv2.zip; \
    ./aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli; \
    rm -rf awscliv2.zip awscliv2.zip.sig aws /tmp/awscli-public-key.asc; \
    aws --version

# --- session-manager-plugin (GPG-verified .deb) ----------------------------
# Drives SSM Session Manager / SSH-over-SSM, the node-access path (docs/ACCESS.md).
# AWS publishes a detached PGP signature for the .deb, signed by its plugin key
# (keyid 2C4D4AFF6F6757EE, distinct from the aws-cli key). The key is COPYed from
# the build context so the verification is real and auditable.
COPY session-manager-plugin-key.asc /tmp/session-manager-plugin-key.asc
RUN set -eux; \
    base="https://s3.amazonaws.com/session-manager-downloads/plugin/${SMP_VERSION}/ubuntu_arm64"; \
    curl -fsSLo smp.deb "${base}/session-manager-plugin.deb"; \
    if [ "${SMP_VERIFY}" = "true" ]; then \
      curl -fsSLo smp.deb.sig "${base}/session-manager-plugin.deb.sig"; \
      gpg --import /tmp/session-manager-plugin-key.asc; \
      gpg --verify smp.deb.sig smp.deb; \
    else \
      echo "WARNING: skipping session-manager-plugin signature verification (SMP_VERIFY=false)"; \
    fi; \
    dpkg -i smp.deb; \
    rm -f smp.deb smp.deb.sig /tmp/session-manager-plugin-key.asc; \
    session-manager-plugin --version

# --- Ansible (+ the collections our roles / k8s work use) ------------------
RUN set -eux; \
    pip3 install --no-cache-dir "ansible-core==${ANSIBLE_CORE_VERSION}"; \
    ansible-galaxy collection install \
      -p /usr/share/ansible/collections \
      "community.general:==${COMMUNITY_GENERAL_VERSION}" \
      "ansible.posix:==${ANSIBLE_POSIX_VERSION}" \
      "kubernetes.core:==${KUBERNETES_CORE_VERSION}" ; \
    ansible --version

# Repo bash helpers (ryderdain/bash) land here at runtime via a volume mount or
# a later build stage; PATH is ready for them.
ENV PATH="/opt/brzl/bin:${PATH}"

# Non-root by default; mount the repo at /work. Generic name `opagent` (this
# image is meant to be reusable beyond this project) — and it avoids the Debian
# system group `operator` would collide with. Own uid/gid 1000 group.
RUN useradd --create-home --uid 1000 --user-group --shell /bin/bash opagent
USER opagent
WORKDIR /work

ENTRYPOINT ["/bin/bash"]
