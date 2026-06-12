#!/usr/bin/env bash
set -euo pipefail

# Release-train version detection.
#
# Git tags are the SINGLE SOURCE OF TRUTH. package.json is never read to
# derive a version: it drifts between branches and caused duplicate/stale
# releases in the past (e.g. staging publishing 0.15.1-beta.N after v0.15.1
# had already shipped stable on main).
#
# Channels:
#   develop -> alpha    staging -> beta    main -> stable
#
# Invariants:
#   * Every computed version is strictly greater than the latest stable
#     release. A pre-release cycle whose base version has already graduated
#     (or been surpassed) is considered closed and is never continued.
#   * staging promotes the newest alpha cycle to beta when that cycle is
#     ahead of both the stable line and the current beta cycle.
#   * The EXACT next version is computed here, in one place. Downstream
#     steps apply it verbatim — no relative "npm version prerelease" math.

BRANCH="${1:?branch required}"

case "$BRANCH" in
  develop) CHANNEL="alpha" ;;
  staging) CHANNEL="beta" ;;
  main)    CHANNEL="stable" ;;
  *)
    echo "::error::Unsupported release-train branch: ${BRANCH}" >&2
    exit 1
    ;;
esac

# ---------- helpers ----------

latest_stable_tag() {
  git tag -l 'v[0-9]*' --sort=-v:refname \
    | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1 || true
}

latest_prerelease_tag() { # $1 = alpha | beta
  git tag -l "v[0-9]*-$1.*" --sort=-v:refname \
    | grep -E "^v[0-9]+\.[0-9]+\.[0-9]+-$1\.[0-9]+$" | head -1 || true
}

base_of() { # vX.Y.Z[-pre.N] -> X.Y.Z
  local v="${1#v}"
  echo "${v%%-*}"
}

base_gt() { # true when base $1 > base $2
  [ "$1" != "$2" ] && [ "$(printf '%s\n' "$1" "$2" | sort -V | tail -1)" = "$1" ]
}

bump_base() { # $1 = X.Y.Z, $2 = major | minor | patch
  local major minor patch
  IFS=. read -r major minor patch <<<"$1"
  case "$2" in
    major) echo "$((major + 1)).0.0" ;;
    minor) echo "${major}.$((minor + 1)).0" ;;
    patch) echo "${major}.${minor}.$((patch + 1))" ;;
    *) echo "::error::Unknown bump type: $2" >&2; exit 1 ;;
  esac
}

next_prerelease_number() { # $1 = base, $2 = preid -> next free N for vBASE-preid.N
  local last
  last=$(git tag -l "v$1-$2.*" --sort=-v:refname \
    | grep -E "^v$1-$2\.[0-9]+$" | head -1 || true)
  if [ -z "$last" ]; then
    echo 0
  else
    echo "$(( ${last##*.} + 1 ))"
  fi
}

# Conventional-commit driven semver bump for opening a new cycle.
resolve_version_bump() { # $1 = since ref (empty = whole history)
  local range log
  if [ -n "$1" ]; then range="$1..HEAD"; else range="HEAD"; fi
  log=$(git log "$range" --pretty='%s%n%b' 2>/dev/null || true)
  if echo "$log" | grep -qiE '^[a-z]+(\([^)]*\))?!:' \
    || echo "$log" | grep -qE '^BREAKING[ -]CHANGE:'; then
    echo "major"
  elif echo "$log" | grep -qiE '^feat(\([^)]*\))?:'; then
    echo "minor"
  else
    echo "patch"
  fi
}

write_github_output() {
  local key="$1" value="$2"
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "${key}=${value}" >> "$GITHUB_OUTPUT"
  else
    echo "${key}=${value}"
  fi
}

# ---------- gather state from tags ----------

STABLE_TAG=$(latest_stable_tag)
STABLE_BASE="${STABLE_TAG#v}"
[ -z "$STABLE_BASE" ] && STABLE_BASE="0.0.0"

ALPHA_TAG=$(latest_prerelease_tag alpha)
BETA_TAG=$(latest_prerelease_tag beta)
ALPHA_BASE=""
BETA_BASE=""
[ -n "$ALPHA_TAG" ] && ALPHA_BASE=$(base_of "$ALPHA_TAG")
[ -n "$BETA_TAG" ] && BETA_BASE=$(base_of "$BETA_TAG")

# ---------- should we release at all? ----------

case "$CHANNEL" in
  alpha)  CHANNEL_TAG="$ALPHA_TAG" ;;
  beta)   CHANNEL_TAG="$BETA_TAG" ;;
  stable) CHANNEL_TAG="$STABLE_TAG" ;;
esac

SHOULD_RELEASE=false
if [ -z "$CHANNEL_TAG" ]; then
  SHOULD_RELEASE=true
elif [ "$(git rev-parse HEAD)" != "$(git rev-parse "${CHANNEL_TAG}^{commit}")" ]; then
  if [ "$(git rev-list "${CHANNEL_TAG}..HEAD" --count)" -gt 0 ]; then
    SHOULD_RELEASE=true
  fi
fi

if [ "$SHOULD_RELEASE" != "true" ]; then
  write_github_output "should_release" "false"
  write_github_output "bump_strategy" "skip"
  write_github_output "release_type" "none"
  write_github_output "version_bump" "patch"
  write_github_output "current_version" "${CHANNEL_TAG#v}"
  write_github_output "next_version" ""
  write_github_output "next_tag" ""
  echo "Release train: no integrated changes since ${CHANNEL_TAG:-<no prior tag>}, skipping release"
  exit 0
fi

# ---------- compute the exact next version ----------

NEXT_VERSION=""
BUMP_STRATEGY=""
VERSION_BUMP="patch"

case "$CHANNEL" in
  alpha)
    if [ -n "$ALPHA_BASE" ] && base_gt "$ALPHA_BASE" "$STABLE_BASE"; then
      # The current alpha cycle is still ahead of stable: continue it.
      BUMP_STRATEGY="prerelease-alpha"
      NEXT_VERSION="${ALPHA_BASE}-alpha.$(next_prerelease_number "$ALPHA_BASE" alpha)"
    else
      # The previous cycle graduated (or never existed): open a new one.
      BUMP_STRATEGY="open-cycle"
      VERSION_BUMP=$(resolve_version_bump "$STABLE_TAG")
      FLOOR="$STABLE_BASE"
      # Stay ahead of any beta cycle staging may have opened independently.
      if [ -n "$BETA_BASE" ] && base_gt "$BETA_BASE" "$FLOOR"; then
        FLOOR="$BETA_BASE"
      fi
      NEW_BASE=$(bump_base "$FLOOR" "$VERSION_BUMP")
      NEXT_VERSION="${NEW_BASE}-alpha.$(next_prerelease_number "$NEW_BASE" alpha)"
    fi
    ;;

  beta)
    if [ -n "$BETA_BASE" ] && base_gt "$BETA_BASE" "$STABLE_BASE" \
      && { [ -z "$ALPHA_BASE" ] || ! base_gt "$ALPHA_BASE" "$BETA_BASE"; }; then
      # Current beta cycle has not graduated and no newer alpha cycle exists:
      # iterate it (e.g. a fix merged into staging).
      BUMP_STRATEGY="prerelease-beta"
      NEXT_VERSION="${BETA_BASE}-beta.$(next_prerelease_number "$BETA_BASE" beta)"
    elif [ -n "$ALPHA_BASE" ] && base_gt "$ALPHA_BASE" "$STABLE_BASE"; then
      # Promote the newest alpha cycle to beta. This is the path that fixes
      # the historical bug: a stale beta of an already-released base is
      # abandoned in favour of the live alpha cycle.
      BUMP_STRATEGY="promote-beta"
      NEXT_VERSION="${ALPHA_BASE}-beta.$(next_prerelease_number "$ALPHA_BASE" beta)"
    else
      # Nothing upstream is ahead of stable (e.g. hotfix merged straight to
      # staging): open a fresh cycle from the stable line.
      BUMP_STRATEGY="open-cycle-beta"
      VERSION_BUMP=$(resolve_version_bump "$STABLE_TAG")
      NEW_BASE=$(bump_base "$STABLE_BASE" "$VERSION_BUMP")
      NEXT_VERSION="${NEW_BASE}-beta.$(next_prerelease_number "$NEW_BASE" beta)"
    fi
    ;;

  stable)
    if [ -n "$BETA_BASE" ] && base_gt "$BETA_BASE" "$STABLE_BASE"; then
      BUMP_STRATEGY="graduate"
      NEXT_VERSION="$BETA_BASE"
    elif [ -n "$ALPHA_BASE" ] && base_gt "$ALPHA_BASE" "$STABLE_BASE"; then
      # develop merged straight to main, skipping staging.
      BUMP_STRATEGY="graduate"
      NEXT_VERSION="$ALPHA_BASE"
    else
      # Hotfix merged straight to main.
      BUMP_STRATEGY="hotfix-stable"
      VERSION_BUMP=$(resolve_version_bump "$STABLE_TAG")
      NEXT_VERSION=$(bump_base "$STABLE_BASE" "$VERSION_BUMP")
    fi
    ;;
esac

# ---------- safety net ----------

if git rev-parse -q --verify "refs/tags/v${NEXT_VERSION}" >/dev/null; then
  echo "::error::Computed tag v${NEXT_VERSION} already exists. Refusing to overwrite an existing release." >&2
  exit 1
fi

NEXT_BASE=$(base_of "$NEXT_VERSION")
if ! base_gt "$NEXT_BASE" "$STABLE_BASE"; then
  echo "::error::Computed version ${NEXT_VERSION} does not advance past latest stable ${STABLE_BASE}. Aborting." >&2
  exit 1
fi

case "$CHANNEL" in
  alpha)  RELEASE_TYPE="alpha" ;;
  beta)   RELEASE_TYPE="beta" ;;
  stable) RELEASE_TYPE="stable" ;;
esac

write_github_output "should_release" "true"
write_github_output "bump_strategy" "$BUMP_STRATEGY"
write_github_output "release_type" "$RELEASE_TYPE"
write_github_output "version_bump" "$VERSION_BUMP"
write_github_output "current_version" "${CHANNEL_TAG#v}"
write_github_output "next_version" "$NEXT_VERSION"
write_github_output "next_tag" "v${NEXT_VERSION}"

echo "Release train: ${BRANCH} (${BUMP_STRATEGY}) -> v${NEXT_VERSION} [stable=${STABLE_BASE} beta=${BETA_TAG:-none} alpha=${ALPHA_TAG:-none}]"
