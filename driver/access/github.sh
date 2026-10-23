#!/usr/bin/env bash
# github.sh — give the platform read access to a private workload on GitHub
# (ADR-0034): a GitHub App on the workload's organization, read-only, for
# Argo CD and the ApplicationSet's SCM generator, and a token with
# read:packages for the registry's pull-through of the workload's image.
# And sign-on (ADR-0035, pass 6a): the teams of the three access tiers, and
# one GitHub OAuth App for each environment, which Dex signs people in with.
# GitHub-specific; an alternative host gets its own script with the same
# output layout (BACKLOG 22).
#
# Output: var/access/github/<org>/ (gitignored), the contract phase 25-bootstrap
# reads once to seed the cluster secret store:
#   app-id  app-slug  app.pem  installation-id  packages-user  packages-token
#   oauth-<env>-client-id  oauth-<env>-client-secret        (sign-on)
#
# Steps, in this order; each one is an emit script (preview it, then pipe it
# to bash on this machine, where gh is logged in), except `check`:
#   bash driver/access/github.sh app_manifest <org>          # the App's form, in the browser
#   bash driver/access/github.sh app_convert <org> <code>    # the code from the browser's URL
#   bash driver/access/github.sh app_install <org>           # install it, in the browser
#   bash driver/access/github.sh installation <org>          # the installation id
#   bash driver/access/github.sh packages_token <org>        # the token page, in the browser
#   bash driver/access/github.sh check <org>/<repo>          # GENERATOR: verify all of it
# Sign-on, for the organization of the access tiers (BRZL_SIGN_ON_ORG):
#   bash driver/access/github.sh teams <org>                 # the three teams; you in brzl-admins
#   bash driver/access/github.sh oauth_app <org> <env>       # the OAuth App's form, in the browser
#   bash driver/access/github.sh sign_on_check <org> <env>   # GENERATOR: verify it
#
# Needs: gh (logged in; `installation` and `teams` need the admin:org scope),
# jq, curl.
# Credentials: your own GitHub login in gh; the files written are the
# platform's. Nothing is printed: the App's key and the token go to files
# with mode 0600.

(( BASH_VERSINFO[0] < 4 )) && { printf 'error: bash >= 4 required\n' >&2; exit 1; }
(return 0 2>/dev/null) && is_sourced=true || is_sourced=false

repo_root="$(cd -- "${BASH_SOURCE[0]%/*}/../.." && pwd -P)" || exit 1
# shellcheck source=SCRIPTDIR/../lib/runlib.sh
source "$repo_root/driver/lib/runlib.sh" || exit 1
# shellcheck source=SCRIPTDIR/../lib/phase-common.sh
source "$repo_root/driver/lib/phase-common.sh" || exit 1

platform_url=https://github.com/ryderdain/barzel-cluster

access_dir() { printf 'var/access/github/%s' "$1"; }

# app_name <org> — the App's name; GitHub App names are unique site-wide.
app_name() { printf 'brzl-reader-%s' "$1"; }

# open_cmd — the command that opens a file or URL in the browser, for the
# driver machine's OS.
open_cmd() {
  case "$(host_os)" in
    Darwin) printf 'open' ;;
    *) printf 'xdg-open' ;;
  esac
}

need_org() {
  if [[ -z "${1:-}" ]]; then
    printf 'usage: github.sh %s <org>\n' "$2" >&2
    return 2
  fi
}

# app_manifest <org> — EMIT: write the manifest form and open it. GitHub has no
# API that makes an App; the manifest flow is a form the browser posts.
app_manifest() {
  local org="$1" dir manifest
  need_org "$org" app_manifest || end_function "$?" 'usage'
  dir="$(access_dir "$org")"
  manifest="$(jq -nc --arg name "$(app_name "$org")" --arg url "$platform_url" --arg org "$org" '{
    name: $name,
    url: $url,
    description: ("Read-only access for the barzel-cluster platform: Argo CD and its SCM generator read the manifests of " + $org + "'"'"'s workloads."),
    public: false,
    redirect_url: ("https://github.com/organizations/" + $org + "/settings/apps"),
    hook_attributes: { url: ($url + "/hooks/unused"), active: false },
    default_permissions: { contents: "read", metadata: "read" }
  }')" || end_function "$?" 'manifest'
  printf 'cd %q || exit 1\n' "$repo_root"
  printf '{ # the GitHub App'"'"'s manifest, as a form the browser posts to GitHub (%s)\n' "$org"
  printf '  mkdir -p %q\n' "$dir"
  printf "  cat > %q <<'EOF'\n" "$dir/app-manifest.html"
  cat <<EOF
<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>Create the GitHub App for $org</title></head>
<body style="font: 16px system-ui; max-width: 40rem; margin: 3rem auto">
<h1>barzel-cluster: the GitHub App for <code>$org</code></h1>
<p>This form registers the App <code>$(app_name "$org")</code> on the organization
<code>$org</code>: read-only (contents, metadata), no webhooks, private.</p>
<form method="post" action="https://github.com/organizations/$org/settings/apps/new?state=brzl">
  <input type="hidden" name="manifest" value='$(sed "s/'/\&#39;/g" <<< "$manifest")'>
  <button type="submit" style="font-size: 1.1rem; padding: .6rem 1.2rem">Create the GitHub App on GitHub</button>
</form>
</body></html>
EOF
  printf 'EOF\n'
  printf '  %s %q\n' "$(open_cmd)" "$dir/app-manifest.html"
  printf '}\n'
  operator_step "to register the App: in the page that opened, press the button, then on GitHub press \"Create GitHub App\". GitHub sends you to the organization's App settings; copy the code from the address bar (?code=...). Then, within one hour:" \
    "bash driver/access/github.sh app_convert $org <code> | bash"
  end_function 0 "emitted the App manifest for $org"
}

# app_convert <org> <code> — EMIT: exchange the code for the App's id, slug and
# private key. The response holds secrets, so it goes to a 0600 file and is
# split there; nothing is printed.
app_convert() {
  local org="$1" code="${2:-}" dir
  need_org "$org" 'app_convert' || end_function "$?" 'usage'
  if [[ -z "$code" ]]; then
    printf 'usage: github.sh app_convert <org> <code>\n' >&2
    end_function 2 'usage'
    return 2
  fi
  dir="$(access_dir "$org")"
  printf 'cd %q || exit 1\n' "$repo_root"
  awk '/^error\(\) \{/,/^\}/' "$repo_root/driver/lib/error.sh"
  printf '{ # the App from the code: id, slug and private key into %s (mode 0600)\n' "$dir"
  printf '  umask 077\n'
  printf '  mkdir -p %q\n' "$dir"
  printf '  gh api -X POST %q > %q \\\n' "/app-manifests/$code/conversions" "$dir/app.json"
  printf "    || error 3 'the code was not accepted (it is valid for one hour, once): run app_manifest again'\n"
  printf '  jq -r .id %q > %q\n' "$dir/app.json" "$dir/app-id"
  printf '  jq -r .slug %q > %q\n' "$dir/app.json" "$dir/app-slug"
  printf '  jq -r .pem %q > %q\n' "$dir/app.json" "$dir/app.pem"
  printf '  rm -f %q   # the client secret and webhook secret in it are not used\n' "$dir/app.json"
  printf '  printf '"'"'App %%s (id %%s) registered on %s\\n'"'"' "$(cat %q)" "$(cat %q)"\n' "$org" "$dir/app-slug" "$dir/app-id"
  printf '}\n'
  end_function 0 "emitted the App conversion for $org"
}

# app_install <org> — EMIT: open the App's installation page. Installing is a
# browser step; GitHub has no API for it.
app_install() {
  local org="$1" dir slug
  need_org "$org" app_install || end_function "$?" 'usage'
  dir="$(access_dir "$org")"
  slug="$(cat "$repo_root/$dir/app-slug" 2>/dev/null)" \
    || { printf 'error: no %s/app-slug: run app_manifest and app_convert first\n' "$dir" >&2; end_function 1 'no App yet'; return 1; }
  printf 'cd %q || exit 1\n' "$repo_root"
  printf '{ # the App'"'"'s installation page (%s)\n' "$org"
  printf '  %s %q\n' "$(open_cmd)" "https://github.com/apps/$slug/installations/new"
  printf '}\n'
  operator_step "to install the App: choose the organization $org, then \"Only select repositories\" and the workload's repositories (or all), then Install. Then:" \
    "bash driver/access/github.sh installation $org | bash"
  end_function 0 "emitted the App installation step for $org"
}

# installation <org> — EMIT: the installation id, from the organization's
# installations (needs the admin:org scope on gh's token).
installation() {
  local org="$1" dir
  need_org "$org" installation || end_function "$?" 'usage'
  dir="$(access_dir "$org")"
  [[ -s "$repo_root/$dir/app-id" ]] \
    || { printf 'error: no %s/app-id: run app_manifest and app_convert first\n' "$dir" >&2; end_function 1 'no App yet'; return 1; }
  printf 'cd %q || exit 1\n' "$repo_root"
  awk '/^error\(\) \{/,/^\}/' "$repo_root/driver/lib/error.sh"
  printf '{ # the installation id of App %s on %s\n' "$(cat "$repo_root/$dir/app-id")" "$org"
  printf '  gh api %q --paginate --jq %q > %q \\\n' "/orgs/$org/installations" \
    ".installations[] | select(.app_id == $(cat "$repo_root/$dir/app-id")) | .id" "$dir/installation-id"
  printf "    || error 3 'cannot list the installations of %s: gh needs the admin:org scope (gh auth refresh -h github.com -s admin:org) and you must own the organization'\n" "$org"
  printf '  [[ -s %q ]] \\\n' "$dir/installation-id"
  printf "    || error 3 'the App is not installed on %s yet: run app_install first'\n" "$org"
  printf '  printf '"'"'installation %%s\\n'"'"' "$(cat %q)"\n' "$dir/installation-id"
  printf '}\n'
  end_function 0 "emitted the installation lookup for $org"
}

# packages_token <org> — EMIT: open the token page with read:packages preset,
# record the login the token belongs to, and say where to paste the token.
# GitHub makes tokens only in the browser, and only a classic token can pull
# packages.
packages_token() {
  local org="$1" dir
  need_org "$org" packages_token || end_function "$?" 'usage'
  dir="$(access_dir "$org")"
  printf 'cd %q || exit 1\n' "$repo_root"
  printf '{ # the login the packages token belongs to (the registry wants user and token)\n'
  printf '  umask 077\n'
  printf '  mkdir -p %q\n' "$dir"
  printf '  gh api user --jq .login > %q\n' "$dir/packages-user"
  printf '  %s %q\n' "$(open_cmd)" "https://github.com/settings/tokens/new?description=brzl-$org-packages&scopes=read:packages"
  printf '}\n'
  operator_step "to make the packages token: on the page that opened, keep only read:packages, generate the token, and copy it." \
    "THE TOKEN GOES INTO THE FILE $dir/packages-token (mode 0600). This writes it from the clipboard:" \
    "  (umask 077; $(clipboard_cmd) > $dir/packages-token)" \
    "then verify everything:" \
    "  bash driver/access/github.sh check $org/<repo>"
  end_function 0 "emitted the packages token step for $org"
}

# The teams of the access tiers (Q169, Q170, Q182): one set for every
# environment; each environment decides what each tier may do. The same
# names are in Dex's, Argo CD's, Grafana's and oauth2-proxy's values
# (gitops/infrastructure/sign-on/, argocd/, monitoring/).
tier_teams=(brzl-admins brzl-operators brzl-auditors)

# clipboard_cmd — the command that prints the clipboard, for the driver
# machine's OS.
clipboard_cmd() {
  case "$(host_os)" in
    Darwin) printf 'pbpaste' ;;
    *) printf 'xclip -o -selection clipboard' ;;
  esac
}

# shellcheck disable=SC2016  # $me is for the emitted stream to expand
# teams <org> — EMIT: make the three teams (closed, visible to members) when
# they are absent, and make you a maintainer of brzl-admins only. GitHub adds
# the person who makes a team to it, so the other two teams then lose you.
teams() {
  local org="$1" team
  need_org "$org" teams || end_function "$?" 'usage'
  printf 'cd %q || exit 1\n' "$repo_root"
  awk '/^error\(\) \{/,/^\}/' "$repo_root/driver/lib/error.sh"
  printf '{ # who you are on GitHub\n'
  printf '  me="$(gh api user --jq .login)" \\\n'
  printf "    || error 3 'gh is not logged in: gh auth login'\n"
  printf '}\n'
  for team in "${tier_teams[@]}"; do
    printf '{ # the team %s on %s (an access tier, ADR-0035): make it when absent\n' "$team" "$org"
    printf '  gh api %q --silent 2>/dev/null \\\n' "/orgs/$org/teams/$team"
    printf '    || gh api -X POST %q -f name=%q -f privacy=closed \\\n' "/orgs/$org/teams" "$team"
    printf '         -f description=%q --silent\n' "barzel-cluster access tier ($team)"
    if [[ "$team" == brzl-admins ]]; then
      printf '  gh api -X PUT "%s/$me" -f role=maintainer --silent\n' "/orgs/$org/teams/$team/memberships"
    else
      # When you are not a member, GitHub answers 404: visible, and harmless.
      printf '  gh api -X DELETE "%s/$me" --silent\n' "/orgs/$org/teams/$team/memberships"
    fi
    printf '}\n'
  done
  end_function 0 "emitted the teams for $org"
}

# oauth_app <org> <env> — EMIT: open the organization's form for a new OAuth
# App and print the values to type in. GitHub has no API that makes an OAuth
# App. An App has one callback URL, so each environment has its own. The
# client id and secret go from the clipboard into two files, mode 0600.
oauth_app() {
  local org="$1" env="${2:-}" dir host
  need_org "$org" oauth_app || end_function "$?" 'usage'
  if [[ -z "$env" ]]; then
    printf 'usage: github.sh oauth_app <org> <env>\n' >&2
    end_function 2 'usage'
    return 2
  fi
  phase_init "$env" || end_function "$?" 'environment definition'
  dir="$(access_dir "$org")"; host="$BRZL_PORTAL_HOST"
  printf 'cd %q || exit 1\n' "$repo_root"
  printf '{ # the form for a new OAuth App on %s (sign-on for %s)\n' "$org" "$env"
  printf '  mkdir -p %q\n' "$dir"
  printf '  %s %q\n' "$(open_cmd)" "https://github.com/organizations/$org/settings/applications/new"
  printf '}\n'
  operator_step "to register the OAuth App: on the page that opened, type in" \
    "  Application name:            brzl-sign-on-$env" \
    "  Homepage URL:                https://$host/" \
    "  Authorization callback URL:  https://$host/dex/callback" \
    "leave \"Enable Device Flow\" off, then press \"Register application\". Copy the Client ID, then:" \
    "  (umask 077; $(clipboard_cmd) > $dir/oauth-$env-client-id)" \
    "press \"Generate a new client secret\", copy it, then:" \
    "  (umask 077; $(clipboard_cmd) > $dir/oauth-$env-client-secret)" \
    "then verify:" \
    "  bash driver/access/github.sh sign_on_check $org $env"
  end_function 0 "emitted the OAuth App step for $org ($env)"
}

# sign_on_check <org> <env> — GENERATOR: the three teams exist, you are in
# brzl-admins, and the OAuth App's two files are there. GitHub cannot list an
# organization's OAuth Apps through the API, so the App itself is checked at
# the first sign-in.
sign_on_check() {
  local org="$1" env="${2:-}" dir rc=0 team me f
  if [[ -z "$org" || -z "$env" ]]; then
    printf 'usage: github.sh sign_on_check <org> <env>\n' >&2
    return 2
  fi
  require_tools gh jq || return 1
  dir="$(access_dir "$org")"
  me="$(gh api user --jq .login 2>/dev/null)" || { printf 'fix: gh auth login\n' >&2; return 1; }
  for team in "${tier_teams[@]}"; do
    if ! gh api "/orgs/$org/teams/$team" --silent 2>/dev/null; then
      printf 'fix: the team %s/%s is absent: bash driver/access/github.sh teams %s | bash\n' "$org" "$team" "$org" >&2
      rc=1
    fi
  done
  if [[ "$(gh api "/orgs/$org/teams/brzl-admins/memberships/$me" --jq .state 2>/dev/null)" != active ]]; then
    printf 'fix: you (%s) are not an active member of %s/brzl-admins: bash driver/access/github.sh teams %s | bash\n' "$me" "$org" "$org" >&2
    rc=1
  else
    printf 'the teams %s exist on %s; you (%s) are in brzl-admins\n' "${tier_teams[*]}" "$org" "$me"
  fi
  for f in "oauth-$env-client-id" "oauth-$env-client-secret"; do
    if [[ ! -s "$repo_root/$dir/$f" ]]; then
      printf 'fix: %s/%s is missing: bash driver/access/github.sh oauth_app %s %s | bash\n' "$dir" "$f" "$org" "$env" >&2
      rc=1
    fi
  done
  (( rc == 0 )) && printf 'the OAuth App files for %s are in %s (%s bytes of client id)\n' \
    "$env" "$dir" "$(wc -c < "$repo_root/$dir/oauth-$env-client-id" | tr -d ' ')"
  return "$rc"
}

# check <org>/<repo> — GENERATOR: the files are there, the repository is
# reachable, the App is installed on the organization, and the token pulls
# the workload's package (named after the repository).
check() {
  local target="${1:-}" org repo dir rc=0 f perm installed bearer code
  if [[ "$target" != */* ]]; then
    printf 'usage: github.sh check <org>/<repo>\n' >&2
    return 2
  fi
  org="${target%%/*}"; repo="${target#*/}"; dir="$(access_dir "$org")"
  require_tools gh jq curl || return 1
  for f in app-id app-slug app.pem installation-id packages-user packages-token; do
    if [[ ! -s "$repo_root/$dir/$f" ]]; then
      printf 'fix: %s/%s is missing; see the steps in the header of driver/access/github.sh\n' "$dir" "$f" >&2
      rc=1
    fi
  done
  (( rc == 0 )) || return "$rc"
  if ! perm="$(gh repo view "$target" --json isPrivate,viewerPermission --jq '"\(.isPrivate) \(.viewerPermission)"' 2>&1)"; then
    printf 'fix: gh cannot see %s: %s\n' "$target" "$perm" >&2
    return 1
  fi
  printf '%s: private=%s, your permission=%s\n' "$target" "${perm% *}" "${perm#* }"
  installed="$(gh api "/orgs/$org/installations" --paginate --jq ".installations[] | select(.id == $(cat "$repo_root/$dir/installation-id")) | .app_slug" 2>/dev/null)"
  if [[ "$installed" != "$(cat "$repo_root/$dir/app-slug")" ]]; then
    printf 'fix: installation %s of App %s is not on %s (or gh lacks admin:org); run app_install and installation again\n' \
      "$(cat "$repo_root/$dir/installation-id")" "$(cat "$repo_root/$dir/app-slug")" "$org" >&2
    rc=1
  else
    printf 'App %s (id %s) is installed on %s (installation %s)\n' \
      "$installed" "$(cat "$repo_root/$dir/app-id")" "$org" "$(cat "$repo_root/$dir/installation-id")"
  fi
  # The token: a registry token for the package, then its tag list. The
  # token is read from the file by curl itself; it never enters argv.
  bearer="$(curl -sS --user "$(cat "$repo_root/$dir/packages-user"):$(cat "$repo_root/$dir/packages-token")" \
    "https://ghcr.io/token?scope=repository:$org/$repo:pull" 2>/dev/null | jq -r '.token // empty')"
  code="$(curl -sS -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $bearer" \
    "https://ghcr.io/v2/$org/$repo/tags/list" 2>/dev/null)"
  if [[ "$code" != 200 ]]; then
    printf 'fix: the packages token cannot read ghcr.io/%s/%s (HTTP %s): the token needs read:packages, and the package must exist (CI publishes it on the first push)\n' \
      "$org" "$repo" "$code" >&2
    rc=1
  else
    printf 'the packages token pulls ghcr.io/%s/%s\n' "$org" "$repo"
  fi
  return "$rc"
}

if [[ "$is_sourced" == false ]]; then
  if (( $# )); then "$@"; else sed -n '2,25p' "${BASH_SOURCE[0]}"; fi
fi
