#cloud-config
# Bootstrap VM (SPEC §4.2) — a throwaway host that runs the pinned toolbox
# container for the chicken-egg first apply and for long ops (bootstrap, k8s/PG
# upgrades), so execution outlives an operator's SSO/SSH session timing out.
#
# Rendered by Terraform `templatefile()` (same pattern as
# modules/compute/user_data.yaml.tpl) so no account id / registry is committed —
# ${...} are Terraform interpolations, filled at apply time. The launching
# instance needs an instance profile that can (a) pull from ECR and (b) assume
# the brzl-tofu-apply role — no static credentials.
#
# Immutable production path (documented, not built here): bake this toolchain
# into an AMI with Packer instead of installing at boot.

package_update: true
package_upgrade: true
packages:
  - podman      # daemonless, rootless-capable: no docker socket to expose
  - awscli      # only for `ecr get-login-password` (uses the instance profile)

write_files:
  # Convenience shell env: a `toolbox` alias that runs the pinned image with the
  # current dir mounted at /work.
  - path: /etc/profile.d/brzl-toolbox.sh
    permissions: '0644'
    content: |
      export BRZL_TOOLBOX="${registry}/${toolbox_image}:${toolbox_tag}"
      export AWS_DEFAULT_REGION="${aws_region}"
      alias toolbox='podman run --rm -it -v "$PWD":/work -w /work "$BRZL_TOOLBOX"'

  # Log in to ECR with the INSTANCE PROFILE (no static creds) and pull the
  # pinned toolbox. Explicit return-code checks rather than `set -euo pipefail`
  # (CLAUDE.md / BashPitfalls): we check the two commands whose failure matters.
  - path: /usr/local/bin/brzl-pull-toolbox
    permissions: '0755'
    content: |
      #!/usr/bin/env bash
      if ! token="$(aws ecr get-login-password --region "${aws_region}")"; then
        printf 'ecr: could not get login password — is an instance profile attached?\n' >&2
        exit 1
      fi
      if ! printf '%s' "$token" | podman login --username AWS --password-stdin "${registry}"; then
        printf 'ecr: podman login failed\n' >&2
        exit 1
      fi
      podman pull "${registry}/${toolbox_image}:${toolbox_tag}"

runcmd:
  - [systemctl, enable, --now, podman.socket]
  - [bash, -lc, "brzl-pull-toolbox"]

final_message: "brzl bootstrap VM ready; toolbox pulled. Run: toolbox"
