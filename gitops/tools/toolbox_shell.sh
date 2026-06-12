#!/usr/bin/env bash
# toolbox_shell.sh — drop into an interactive shell on the operator toolbox
# IN-CLUSTER, so you can inspect from inside the pod network (ClusterIPs,
# CoreDNS, CNPG pods) and run the pinned toolchain baked into the image
# (tofu / kubectl / helm / aws / argocd / cnpg / trivy / …).
#
#   AWS_PROFILE=brzl-apply bash gitops/tools/toolbox_shell.sh
#   TOOLBOX_TAG=2026-06-03 AWS_PROFILE=brzl-apply bash gitops/tools/toolbox_shell.sh
#
# How it works: the toolbox image lives in ECR (brzl-dev/toolbox). k3s has no
# standing ECR auth, so each run refreshes a short-lived (~12h) ECR
# imagePullSecret and binds it to a `toolbox` ServiceAccount; the pod runs as
# that SA so in-pod kubectl works too. The pod is --rm (removed on exit); the
# SA / binding / secret persist for fast re-entry.
#
# PREREQ: the image must be built + pushed first (one-time setup):
#   - add a `toolbox` repo to 40-ecr and apply
#   - docker buildx build --platform linux/arm64 -t <registry>/brzl-dev/toolbox:<tag> --push containers/toolbox
# This script fails fast (below) if the tag isn't in ECR yet.
#
# SECURITY: the toolbox SA is bound to cluster-admin by default (a dev
# inspection convenience). Override with TOOLBOX_CLUSTERROLE=view for read-only,
# or remove it afterwards:
#   kubectl delete clusterrolebinding toolbox-binding
#   kubectl -n <ns> delete sa toolbox; kubectl -n <ns> delete secret ecr-toolbox
#
# No `set -euo pipefail` (CLAUDE.md / BashPitfalls/105): each AWS/kubectl step
# whose failure matters is checked explicitly.

if (( BASH_VERSINFO[0] < 4 )); then
  printf 'error: bash >= 4 required\n' >&2
  exit 1
fi

region="${AWS_REGION:-eu-central-1}"
repo="${TOOLBOX_REPO:-brzl-dev/toolbox}"
tag="${TOOLBOX_TAG:-}"  # empty = resolve the newest pushed tag (content-addressed; see 40-ecr/toolbox.tf)
namespace="${TOOLBOX_NAMESPACE:-default}"
clusterrole="${TOOLBOX_CLUSTERROLE:-cluster-admin}"
sa="toolbox"
secret="ecr-toolbox"

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
export KUBECONFIG="${KUBECONFIG:-${script_dir}/../../ansible/.kube/config-dev.yaml}"

for tool in aws kubectl; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'error: %s not found on PATH\n' "$tool" >&2
    exit 1
  fi
done
if [[ ! -r "$KUBECONFIG" ]]; then
  printf 'error: kubeconfig not readable: %s (run the kubernetes role first)\n' "$KUBECONFIG" >&2
  exit 1
fi

# Resolve the ECR registry host from the caller's account.
if ! account="$(aws sts get-caller-identity --query Account --output text 2>&1)"; then
  printf 'error: could not resolve AWS account (creds set?):\n%s\n' "$account" >&2
  exit 1
fi
registry="${account}.dkr.ecr.${region}.amazonaws.com"

# Resolve the newest pushed tag when one wasn't pinned (the build is
# content-addressed, so there's no fixed `latest`). This also fails fast if the
# toolbox hasn't been built/pushed yet — otherwise the pod just ImagePullBackOffs.
if [[ -z "$tag" ]]; then
  if ! tag="$(aws ecr describe-images --region "$region" --repository-name "$repo" \
    --query 'sort_by(imageDetails,&imagePushedAt)[-1].imageTags[0]' --output text 2>&1)"; then
    printf 'error: could not list toolbox images in ECR:\n%s\n' "$tag" >&2
    printf '       build + push first: apply 40-ecr, or run containers/toolbox/build_push.sh | bash\n' >&2
    exit 1
  fi
  if [[ -z "$tag" || "$tag" == "None" ]]; then
    printf 'error: no tagged toolbox image in %s — build + push first (apply 40-ecr).\n' "$repo" >&2
    exit 1
  fi
fi
image="${registry}/${repo}:${tag}"

# Refresh the ECR pull secret (token lasts ~12h) and bind it to the SA.
if ! token="$(aws ecr get-login-password --region "$region" 2>&1)"; then
  printf 'error: ecr get-login-password failed:\n%s\n' "$token" >&2
  exit 1
fi
kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n "$namespace" create serviceaccount "$sa" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n "$namespace" create secret docker-registry "$secret" \
  --docker-server="$registry" --docker-username=AWS --docker-password="$token" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n "$namespace" patch serviceaccount "$sa" \
  -p "{\"imagePullSecrets\":[{\"name\":\"${secret}\"}]}" >/dev/null
kubectl create clusterrolebinding "toolbox-binding" \
  --clusterrole="$clusterrole" --serviceaccount="${namespace}:${sa}" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

pod="toolbox-$(id -un | tr '[:upper:]._' '[:lower:]--')-${RANDOM}"
printf 'launching %s as pod %s/%s (SA %s -> %s)\n' "$image" "$namespace" "$pod" "$sa" "$clusterrole" >&2

# `kubectl run` dropped --serviceaccount in newer kubectl; set it via --overrides
# (the pull secret rides on the SA, so serviceAccountName is all we need here).
exec kubectl -n "$namespace" run "$pod" \
  --rm -it --restart=Never \
  --image="$image" --image-pull-policy=Always \
  --overrides="{\"spec\":{\"serviceAccountName\":\"${sa}\"}}" \
  --command -- bash
