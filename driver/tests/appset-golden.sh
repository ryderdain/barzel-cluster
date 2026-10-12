#!/usr/bin/env bash
# appset-golden.sh — the golden render test for the AWS ApplicationSets
# (gitops/clusters/{dev,prod}). It proves that a change to an ApplicationSet
# does not change the Applications that dev or prod get (ADR-0016: a renamed
# Application is pruned, and its finalizer deletes what it deployed).
#
# Method: a disposable k3d cluster (brzl-golden) runs Argo CD only. The test
# applies the env's AppProject, a cluster Secret that points to
# https://<env>.invalid (so nothing can sync) with placeholder annotations, and
# the env's ApplicationSet. The ApplicationSet controller renders the
# Applications; `capture` prints them in a stable form; `compare` diffs them
# with the committed golden file driver/tests/golden/appset-<env>.json.
#
# Emit + generator, one function each:
#   bash driver/tests/appset-golden.sh up <env> | bash driver/kiesei.sh   # EMIT
#   bash driver/tests/appset-golden.sh capture <env> [file]               # GENERATOR
#   bash driver/tests/appset-golden.sh compare <env>                      # GENERATOR
#   bash driver/tests/appset-golden.sh down | bash driver/kiesei.sh       # EMIT
# <env> is dev or prod. One env per cluster: both render Applications with the
# same names. Run `down` before the next env.
#
# Inputs: env/local.env (BRZL_K3S_IMAGE); var/golden/kubeconfig from `up`.
# Needs k3d, helm, kubectl, jq (all in kiesei). No credentials: the account
# values are documentation placeholders (123456789012), never real ones.

(return 0 2>/dev/null) && is_sourced=true || is_sourced=false

repo_root="$(cd -- "${BASH_SOURCE[0]%/*}/../.." && pwd -P)" || exit 1
# shellcheck source=SCRIPTDIR/../lib/runlib.sh
source "$repo_root/driver/lib/runlib.sh" || exit 1

cluster=brzl-golden
api_port=6551
work_dir=var/golden
# The argo-cd chart version of the `argocd` element in the ApplicationSets.
argocd_chart_version=7.7.0
placeholder_account=123456789012

check_env() {
  case "$1" in
    dev | prod) return 0 ;;
    *) printf 'usage: appset-golden.sh {up|capture|compare} <dev|prod>\n' >&2; return 2 ;;
  esac
}

up() {
  local env="${1:-}" secret
  check_env "$env" || end_function "$?" 'environment'
  load_env_definition "$repo_root/env/local.env" || end_function "$?" 'environment definition'
  secret="$(<"$repo_root/gitops/clusters/$env/in-cluster.yaml")" \
    || end_function "$?" 'cluster Secret manifest'
  secret="${secret//https:\/\/kubernetes.default.svc/https://$env.invalid}"
  printf 'cd %q\n' "$repo_root"
  printf '{ # disposable cluster %s: Argo CD only, no workloads\n' "$cluster"
  printf '  mkdir -p %q\n' "$work_dir"
  printf '  k3d cluster create %q --image %q --api-port %q --wait\n' \
    "$cluster" "$BRZL_K3S_IMAGE" "127.0.0.1:$api_port"
  printf '  k3d kubeconfig get %q > %q\n' "$cluster" "$work_dir/kubeconfig"
  printf '}\n'
  printf 'export KUBECONFIG=%q\n' "$work_dir/kubeconfig"
  printf '{ # Argo CD from the upstream image (the repo values route it through ECR)\n'
  printf '  helm repo add argo https://argoproj.github.io/argo-helm\n'
  printf '  helm repo update argo\n'
  printf '  helm upgrade --install argocd argo/argo-cd --version %q \\\n' "$argocd_chart_version"
  printf '    --namespace argocd --create-namespace -f gitops/infrastructure/argocd/values.yaml \\\n'
  printf '    --set global.image.repository=quay.io/argoproj/argocd --wait\n'
  printf '}\n'
  printf '{ # %s inputs: AppProject, a cluster Secret that cannot be reached, the ApplicationSet\n' "$env"
  printf '  kubectl apply -f %q\n' "gitops/clusters/$env/project.yaml"
  printf "  kubectl apply -f - <<'EOF'\n%s\nEOF\n" "$secret"
  printf '  kubectl annotate --overwrite -n argocd secret %q \\\n' "brzl-$env-in-cluster"
  printf '    %q %q\n' "brzl.dev/ecr-host=$placeholder_account.dkr.ecr.eu-central-1.amazonaws.com" \
    "brzl.dev/backup-bucket=brzl-$env-cnpg-backups-$placeholder_account"
  printf '  kubectl apply -f %q\n' "gitops/clusters/$env/applicationset.yaml"
  printf '  kubectl -n argocd wait %q --for=condition=ResourcesUpToDate --timeout=180s\n' \
    "applicationset/brzl-$env"
  printf '}\n'
  end_function 0 "emitted appset-golden up $env"
}

down() {
  printf '{ # remove the disposable cluster %s\n' "$cluster"
  printf '  k3d cluster delete %q\n' "$cluster"
  printf '  rm -f %q\n' "$repo_root/$work_dir/kubeconfig"
  printf '}\n'
  end_function 0 'emitted appset-golden down'
}

# The rendered Applications in a stable form: name, labels, sync wave,
# finalizers and the whole spec, sorted by name. Status is left out: it
# depends on time and on the unreachable cluster.
render() {
  local env="$1" json
  export KUBECONFIG="$repo_root/$work_dir/kubeconfig"
  if ! json="$(kubectl -n argocd get applications -o json)"; then
    printf 'fix: no Applications to read; run: bash driver/tests/appset-golden.sh up %s | bash driver/kiesei.sh\n' \
      "$env" >&2
    return 1
  fi
  jq -S '[.items[] | {
      name: .metadata.name,
      labels: .metadata.labels,
      wave: .metadata.annotations["argocd.argoproj.io/sync-wave"],
      finalizers: .metadata.finalizers,
      spec: .spec
    }] | sort_by(.name)' <<< "$json"
}

capture() {
  local env="${1:-}" target="${2:-}" out
  check_env "$env" || return 2
  out="$(render "$env")" || return 1
  emit_to "$out" "$target"
}

compare() {
  local env="${1:-}" golden
  check_env "$env" || return 2
  golden="$repo_root/driver/tests/golden/appset-$env.json"
  if [[ ! -r "$golden" ]]; then
    printf 'fix: no golden file; capture one: bash driver/tests/appset-golden.sh capture %s %q\n' \
      "$env" "$golden" >&2
    return 1
  fi
  if ! diff -u "$golden" <(render "$env"); then
    printf 'fix: the %s Applications differ from the golden file (above). If the change is intended, capture it again.\n' \
      "$env" >&2
    return 1
  fi
  printf 'the %s Applications match the golden file\n' "$env"
}

if [[ "$is_sourced" == false ]]; then
  if (( $# )); then "$@"; else sed -n '2,25p' "${BASH_SOURCE[0]}"; fi
fi
