#!/usr/bin/env bash
set -euo pipefail

# Pure candidate-selection logic for image-tag-cleanup. Never touches a
# registry itself — cleanup-dockerhub.sh / cleanup-ghcr.sh fetch the real
# data and call this to decide what's safe to delete.
#
# Reads a JSON array on stdin: [{"id":"<registry-specific id>","tags":["..."],"updated_at":"<ISO8601>"}, ...]
# Prints a JSON array of "id"s eligible for deletion.
#
# Safety guarantee: an entry is a deletion CANDIDATE only when EVERY one of
# its tags starts with $PREFIX. An entry carrying any tag that doesn't match
# — a stable release (vX.Y.Z), :latest, :edge, a legacy release-train tag
# (:alpha, :beta, :X.Y.Z-alpha.N, ...) — is always protected and never even
# considered, regardless of age. Among candidates, the $KEEP_MIN most
# recently updated are always kept regardless of age; the rest are selected
# for deletion only once older than $RETENTION_DAYS days.

PREFIX="${1:?ephemeral tag prefix required}"
RETENTION_DAYS="${2:?retention_days required}"
KEEP_MIN="${3:?keep_min required}"
NOW="${4:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

jq -c \
  --arg prefix "$PREFIX" \
  --argjson retention_days "$RETENTION_DAYS" \
  --argjson keep_min "$KEEP_MIN" \
  --arg now "$NOW" '
  def is_ephemeral: (.tags | length > 0) and (.tags | all(startswith($prefix)));

  [ .[] | select(is_ephemeral) ]
  | sort_by(.updated_at) | reverse
  | to_entries
  | [ .[]
      | select(.key >= $keep_min)
      | . as $e
      | (($now | fromdateiso8601) - ($e.value.updated_at | fromdateiso8601)) as $age_seconds
      | select($age_seconds > ($retention_days * 86400))
      | $e.value.id
    ]
'
