#cloud-config
# Conductor cloud-init (00-conductor) — installs a PINNED arm64 operator toolchain
# directly on the host so every operator drives infra with the identical toolset
# (goal #1), reached only via SSM (goals #2/#3). Deliberately self-contained: it does
# NOT pull the ECR toolbox image, so the conductor works even while 40-ecr is being
# (re)built during A2. (Production refinement: converge onto the pinned ECR toolbox
# image — containers/toolbox/ — or a Packer AMI; documented, not done here.)
#
# Rendered by Terraform templatefile(): a doubled dollar-brace escapes a shell
# expansion (templatefile leaves it alone); a single dollar-brace is a Terraform
# interpolation filled at apply (aws_region, git_repo_url, the pinned versions).

package_update: true
packages:
  - git
  - jq
  - unzip
  - tar
  - python3-pip
  - docker

# Pre-create the docker group + ssm-user IN it. The toolbox image build (40-ecr's
# terraform_data.toolbox_image → docker build) runs on this box as the SSM session
# user, which is ssm-user. SSM creates ssm-user lazily on the FIRST session — too late
# for a cloud-init `usermod` — so we create it up front as a docker member and let the
# SSM agent reuse it (AWS: an existing ssm-user is used as-is). The docker group is
# declared here too so it exists before the docker package's own group-add. No socket
# permission relaxation needed — ssm-user is a real group member, socket stays 0660.
groups:
  - docker
users:
  - default
  - name: ssm-user
    groups: docker
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL

write_files:
  # Pinned-toolchain installer. arm64-only (the conductor is Graviton). Explicit
  # &&-chaining + pipefail rather than `set -e` (CLAUDE.md / BashPitfalls): each
  # tool installs independently and logs its own failure to the cloud-init log.
  - path: /usr/local/bin/brzl-install-toolchain
    permissions: '0755'
    content: |
      #!/usr/bin/env bash
      set -o pipefail
      arch=arm64
      log() { printf '[brzl-toolchain] %s\n' "$*"; }

      log "OpenTofu ${tofu_version}"
      curl -fsSL "https://github.com/opentofu/opentofu/releases/download/v${tofu_version}/tofu_${tofu_version}_linux_$${arch}.zip" -o /tmp/tofu.zip \
        && unzip -o /tmp/tofu.zip tofu -d /usr/local/bin/ && chmod +x /usr/local/bin/tofu \
        || log "WARN: tofu install failed"

      log "kubectl ${kubectl_version}"
      curl -fsSL "https://dl.k8s.io/release/v${kubectl_version}/bin/linux/$${arch}/kubectl" -o /usr/local/bin/kubectl \
        && chmod +x /usr/local/bin/kubectl \
        || log "WARN: kubectl install failed"

      log "helm ${helm_version}"
      curl -fsSL "https://get.helm.sh/helm-v${helm_version}-linux-$${arch}.tar.gz" -o /tmp/helm.tgz \
        && tar -xzf /tmp/helm.tgz -C /tmp "linux-$${arch}/helm" \
        && mv "/tmp/linux-$${arch}/helm" /usr/local/bin/helm && chmod +x /usr/local/bin/helm \
        || log "WARN: helm install failed"

      log "ansible-core + collections"
      python3 -m pip install --quiet ansible-core \
        && /usr/local/bin/ansible-galaxy collection install kubernetes.core community.general ansible.posix >/dev/null 2>&1 \
        || log "WARN: ansible install incomplete"

      log "kubectl-cnpg plugin (best-effort)"
      curl -fsSL https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/main/hack/install-cnpg-plugin.sh \
        | bash -s -- -b /usr/local/bin >/dev/null 2>&1 || log "WARN: cnpg plugin skipped"

      # aws-cli v2 ships in the AL2023 base image; confirm it's on PATH.
      command -v aws >/dev/null 2>&1 || log "WARN: aws CLI not found (expected preinstalled on AL2023)"

      # session-manager-plugin: the conductor INITIATES SSM sessions to the k3s
      # nodes for Ansible (the SSH-over-SSM ProxyCommand in ansible/ansible.cfg).
      # `aws ssm start-session` shells out to this plugin, so without it every node
      # connection fails with "SessionManagerPlugin is not found".
      log "session-manager-plugin"
      command -v session-manager-plugin >/dev/null 2>&1 \
        || dnf install -y "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_$${arch}/session-manager-plugin.rpm" >/dev/null 2>&1 \
        || log "WARN: session-manager-plugin install failed"

      # k9s — a terminal UI for watching the cluster (the conductor has no browser /
      # SSO ingress; this is the operator's at-a-glance view). It is a read-only
      # MONITOR, not an IaC executor, so it tracks `latest` rather than being pinned
      # like tofu/kubectl/helm — a stale pin would only WARN, and the TUI doesn't
      # affect cluster state.
      log "k9s (latest)"
      curl -fsSL "https://github.com/derailed/k9s/releases/latest/download/k9s_Linux_$${arch}.tar.gz" -o /tmp/k9s.tgz \
        && tar -xzf /tmp/k9s.tgz -C /usr/local/bin k9s && chmod +x /usr/local/bin/k9s \
        || log "WARN: k9s install failed"
      log "done: $(tofu version 2>/dev/null | head -1) / kubectl $(kubectl version --client -o yaml 2>/dev/null | grep -m1 gitVersion || true)"

  # brzl-fetch [dest] — fetch the operator's APPROVED working tree from the state
  # bucket (shipped by gitops/tools/ship_repo.sh on the laptop) and extract it, using
  # this box's INSTANCE ROLE. No GitHub credential, no clone: the conductor runs exactly
  # the snapshot the operator pushed over the audited channel (CLAUDE.md §1.8 — laptop
  # reads/approves, the toolbox executes). The bucket name is derived from this box's
  # own account id; the tarball excludes gitignored files (the conductor makes its own
  # backend.hcl). Re-runnable (overwrites in place).
  - path: /usr/local/bin/brzl-fetch
    permissions: '0755'
    content: |
      #!/usr/bin/env bash
      # (templatefile escaping: bare shell vars use a single dollar; brace-forms are
      # doubled. aws_region is a Terraform interpolation filled at apply.)
      # Block until cloud-init's toolchain install has finished, so the operator never
      # has to run `cloud-init status --wait` by hand before driving platform.sh.
      printf 'brzl-fetch: waiting for cloud-init (toolchain) to finish...\n' >&2
      cloud-init status --wait >/dev/null 2>&1 || true
      dest="$${1:-/opt/brzl/brzl-demo}"
      key="$${CONDUCTOR_TRANSFER_KEY:-conductor-transfer/tree.tgz}"
      account="$(aws sts get-caller-identity --query Account --output text 2>/dev/null)"
      if [[ -z "$account" || "$account" == None ]]; then
        printf 'brzl-fetch: could not resolve account (instance role attached?)\n' >&2
        exit 1
      fi
      bucket="brzl-demo-tfstate-$${account}"
      mkdir -p "$dest"
      if aws s3 cp --region ${aws_region} "s3://$${bucket}/$${key}" - | tar xz -C "$dest"; then
        printf 'brzl-fetch: extracted s3://%s/%s → %s\n' "$bucket" "$key" "$dest"
      else
        printf 'brzl-fetch: failed — ship the tree from the laptop first:\n' >&2
        printf '  AWS_PROFILE=brzl-apply bash gitops/tools/ship_repo.sh | bash\n' >&2
        exit 1
      fi

  # Login hint shown on every SSM shell: where to work + the exact next steps.
  - path: /etc/profile.d/brzl-conductor.sh
    permissions: '0644'
    content: |
      export AWS_DEFAULT_REGION="${aws_region}"
      export BRZL_WORKDIR=/opt/brzl
      # SSM drops operators into POSIX sh; re-exec into a bash login shell once (the
      # BRZL_BASHED guard + login re-exec means /etc/profile.d is re-read and this
      # block falls through to the banner instead of looping).
      case "$-" in
        *i*)
          if [ -z "$${BRZL_BASHED:-}" ] && command -v bash >/dev/null 2>&1; then
            BRZL_BASHED=1; export BRZL_BASHED
            exec bash -l
          fi
          ;;
      esac
      cat <<'BANNER'
      ── brzl conductor ───────────────────────────────────────────────────────
      Pinned toolchain: tofu / kubectl / helm / ansible / aws / session-manager-plugin
                        docker / git / jq / k9s (watch the cluster: just run `k9s`)
      AWS creds        : this box's INSTANCE ROLE (no AWS_PROFILE needed here)
      To drive a bring-up or the DR restore (one orchestrator, platform.sh):
        # (first, from the LAPTOP:  AWS_PROFILE=brzl-apply bash gitops/tools/ship_repo.sh | bash)
        brzl-fetch                                 # pull the approved tree from S3 (instance role; no GitHub cred)
        cd /opt/brzl/brzl-demo
        sed "s/<account_id>/$(aws sts get-caller-identity --query Account --output text)/" \
          terraform/environments/dev/backend.hcl.example > terraform/environments/dev/backend.hcl
        bash gitops/tools/platform.sh preflight     # then: bootstrap (from-zero) | all | restore
      ──────────────────────────────────────────────────────────────────────────
      BANNER

runcmd:
  - [systemctl, enable, --now, docker]
  # ssm-user is already a docker member (users: block above). ec2-user (the default
  # user, used by the SSH-over-SSM path) exists now, so add it here.
  - [bash, -lc, "usermod -aG docker ec2-user 2>/dev/null || true"]
  - [bash, -lc, "install -d -m 0777 /opt/brzl"]
  - [bash, -lc, "/usr/local/bin/brzl-install-toolchain 2>&1 | tee /var/log/brzl-toolchain.log"]

final_message: "brzl conductor ready (toolchain in /var/log/brzl-toolchain.log). Enter with: aws ssm start-session --target <instance-id>"
