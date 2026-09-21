#!/usr/bin/env bash
# Pure helper functions for npm-dual-publish. Sourced by publish.sh, the
# action's preflight step and tests/npm-dual-publish.test.sh. Never touches a
# registry or the network; no function evals its input.

# resolve_app_path <path>
# Prints the path when it is a repository-relative directory. Rejects empty,
# absolute and any path containing a ".." segment.
resolve_app_path() {
  local path="${1-}"
  if [ -z "$path" ]; then
    echo "app_path must not be empty" >&2
    return 1
  fi
  case "$path" in
    /*)
      echo "app_path must be relative, got '${path}'" >&2
      return 1
      ;;
  esac
  case "/${path}/" in
    */../*)
      echo "app_path must not contain '..', got '${path}'" >&2
      return 1
      ;;
  esac
  printf '%s\n' "$path"
}

# validate_scope <package-name> <repository-owner>
# GitHub Packages maps a package to a repository through its scope, so the
# name must be @<owner>/<pkg> (owner compared case-insensitively).
validate_scope() {
  local name="${1-}" owner="${2-}" want scope
  want="@$(printf '%s' "$owner" | tr '[:upper:]' '[:lower:]')"
  case "$name" in
    @*/*) scope="$(printf '%s' "${name%%/*}" | tr '[:upper:]' '[:lower:]')" ;;
    *)
      echo "package name '${name}' is unscoped; GitHub Packages requires '${want}/<name>'" >&2
      return 1
      ;;
  esac
  if [ "$scope" != "$want" ]; then
    echo "package scope '${scope}' does not match the repository owner; GitHub Packages requires '${want}/<name>'" >&2
    return 1
  fi
}

# next_edge_version <stable-version> <run-number>
# Prints <next patch above stable>-edge.<run>, so the edge tag sorts strictly
# above the stable release it accompanies.
next_edge_version() {
  local stable="${1-}" run="${2-}" major minor patch
  if ! [[ "$stable" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "stable version must be X.Y.Z, got '${stable}'" >&2
    return 1
  fi
  major="${BASH_REMATCH[1]}" minor="${BASH_REMATCH[2]}" patch="${BASH_REMATCH[3]}"
  if ! [[ "$run" =~ ^[0-9]+$ ]]; then
    echo "run number must be numeric, got '${run}'" >&2
    return 1
  fi
  printf '%s.%s.%s-edge.%s\n' "$major" "$minor" "$((patch + 1))" "$run"
}

# classify_publish_failure <npm-output>
# Prints "conflict" when the version is already on the registry (safe to
# skip on a re-run) and "failure" for anything else (must fail loudly).
classify_publish_failure() {
  local output="${1-}"
  case "$output" in
    *EPUBLISHCONFLICT* | *"cannot publish over the previously published versions"*)
      echo "conflict"
      ;;
    *)
      echo "failure"
      ;;
  esac
}
