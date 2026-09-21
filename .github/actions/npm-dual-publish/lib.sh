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

# require_root_app_path_for_commit <app_path> <commit_release_files>
# Commit-back uses the @semantic-release/git default assets (CHANGELOG.md and
# package.json at the repository root). Those cannot be scoped to a
# subdirectory from the CLI without also feeding them to the GitHub plugin as
# release assets, so commit-back is only allowed when app_path is ".".
require_root_app_path_for_commit() {
  local path="${1-}" commit="${2-}"
  if [ "$commit" = "true" ] && [ "$path" != "." ]; then
    echo "commit_release_files requires app_path \".\", got '${path}'" >&2
    return 1
  fi
}

# bump_manifest_version <package.json> <stable-version>
# Sets the top-level "version" in place. Formatting is preserved by replacing
# only that line (matched at the file's own indentation, so nested "version"
# keys are never touched); compact JSON falls back to a jq rewrite. The result
# is always verified with jq. Never evals its input.
bump_manifest_version() {
  local file="${1-}" version="${2-}" line lead="" out="" done="false" re tmp
  if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "version must be X.Y.Z, got '${version}'" >&2
    return 1
  fi
  if [ ! -f "$file" ]; then
    echo "manifest not found: '${file}'" >&2
    return 1
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      [[:space:]]*)
        lead="${line%%[![:space:]]*}"
        break
        ;;
    esac
  done <"$file"
  tmp="${file}.tmp"
  if [ -n "$lead" ]; then
    re="^${lead}\"version\"[[:space:]]*:[[:space:]]*\"[^\"]*\"(.*)\$"
    while IFS= read -r line || [ -n "$line" ]; do
      if [ "$done" = "false" ] && [[ "$line" =~ $re ]]; then
        out+="${lead}\"version\": \"${version}\"${BASH_REMATCH[1]}"$'\n'
        done="true"
      else
        out+="${line}"$'\n'
      fi
    done <"$file"
  fi
  if [ "$done" = "true" ]; then
    printf '%s' "$out" >"$tmp"
  else
    jq --arg v "$version" '.version = $v' "$file" >"$tmp" || { rm -f "$tmp"; return 1; }
  fi
  if [ "$(jq -r '.version' "$tmp")" != "$version" ]; then
    rm -f "$tmp"
    echo "failed to set version in '${file}'" >&2
    return 1
  fi
  mv "$tmp" "$file"
}
