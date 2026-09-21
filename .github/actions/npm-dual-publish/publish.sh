#!/usr/bin/env bash
set -euo pipefail

# Publishes one semantic-release version to npmjs and GitHub Packages.
# Invoked by @semantic-release/exec (publishCmd) with the stable version.
#
# Order (stable first, so a failure never leaves `edge` ahead of a stable
# that does not exist): stable->npmjs, stable->GHP, edge->npmjs, edge->GHP.
# A version already on a registry is logged and skipped, so a re-run only
# publishes what is missing.
#
# Env: RUNNER_TEMP, NPM_TOKEN, GHP_TOKEN (falls back to GITHUB_TOKEN), RUN_NUMBER, APP_PATH,
#      PUBLISH_GITHUB_PACKAGES (true|false), GITHUB_REPOSITORY_OWNER,
#      GITHUB_OUTPUT (optional).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib.sh"

STABLE="${1:?stable version required}"
NPMJS_REGISTRY="https://registry.npmjs.org/"
GHP_REGISTRY="https://npm.pkg.github.com/"

APP_PATH="$(resolve_app_path "${APP_PATH:-.}")"
EDGE="$(next_edge_version "$STABLE" "${RUN_NUMBER:?RUN_NUMBER required}")"
cd "$APP_PATH"

# Auth lives in the runner temp dir, never in ~/.npmrc.
NPMJS_RC="${RUNNER_TEMP:?RUNNER_TEMP required}/npmjs.npmrc"
GHP_RC="${RUNNER_TEMP}/ghp.npmrc"
umask 077
printf '//registry.npmjs.org/:_authToken=%s\n' "${NPM_TOKEN:?NPM_TOKEN required}" >"$NPMJS_RC"
printf '//npm.pkg.github.com/:_authToken=%s\n' "${GHP_TOKEN:-${GITHUB_TOKEN:?GHP_TOKEN or GITHUB_TOKEN required}}" >"$GHP_RC"

# Rewrites package.json in the runner only (never committed): sets the
# version and forces publishConfig.registry so a consumer's own
# publishConfig cannot redirect the publish.
set_manifest() { # $1=version $2=registry
  local tmp="package.json.tmp"
  jq --arg v "$1" --arg r "$2" \
    '.version = $v | .publishConfig = ((.publishConfig // {}) + {registry: $r})' \
    package.json >"$tmp"
  mv "$tmp" package.json
}

# publish_one <label> <registry> <npmrc> <tag> <version> <provenance:true|false>
publish_one() {
  local label="$1" registry="$2" rc="$3" tag="$4" version="$5" provenance="$6"
  set_manifest "$version" "$registry"
  local args=(publish --tag "$tag" --registry "$registry" --userconfig "$rc")
  if [ "$provenance" = "true" ]; then
    args+=(--provenance --access public)
  fi
  echo "Publishing ${version} (tag ${tag}) to ${label}"
  local out status=0
  out="$(npm "${args[@]}" 2>&1)" || status=$?
  if [ "$status" -eq 0 ]; then
    echo "Published ${version} to ${label}"
  elif [ "$(classify_publish_failure "$out")" = "conflict" ]; then
    echo "${version} already on ${label}, skipping"
  else
    printf '%s\n' "$out" >&2
    echo "Failed to publish ${version} to ${label}" >&2
    return 1
  fi
}

publish_one npmjs "$NPMJS_REGISTRY" "$NPMJS_RC" latest "$STABLE" true
if [ "${PUBLISH_GITHUB_PACKAGES:-true}" = "true" ]; then
  publish_one "GitHub Packages" "$GHP_REGISTRY" "$GHP_RC" latest "$STABLE" false
fi
publish_one npmjs "$NPMJS_REGISTRY" "$NPMJS_RC" edge "$EDGE" true
if [ "${PUBLISH_GITHUB_PACKAGES:-true}" = "true" ]; then
  publish_one "GitHub Packages" "$GHP_REGISTRY" "$GHP_RC" edge "$EDGE" false
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "published=true"
    echo "version=${STABLE}"
    echo "edge_version=${EDGE}"
  } >>"$GITHUB_OUTPUT"
fi
