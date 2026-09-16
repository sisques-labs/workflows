#!/usr/bin/env bash
set -euo pipefail

# Tests for .github/actions/image-tag-cleanup/select-deletions.sh
#
# Each scenario feeds a synthetic JSON tag/version list on stdin and asserts
# which "id"s come back as deletion candidates. Run locally or in CI:
#   bash tests/image-tag-cleanup-select.test.sh

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SELECT="${REPO_ROOT}/.github/actions/image-tag-cleanup/select-deletions.sh"

PASS=0
FAIL=0
CURRENT_TEST=""

run_select() { # $1=json, $2=prefix, $3=retention_days, $4=keep_min, $5=now
  echo "$1" | bash "$SELECT" "$2" "$3" "$4" "$5"
}

assert_eq() { # $1 = description, $2 = expected, $3 = actual
  if [ "$2" = "$3" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL [${CURRENT_TEST}] $1: expected '$2', got '$3'"
  fi
}

test_case() { CURRENT_TEST="$1"; echo "--- $1"; }

NOW="2026-01-10T00:00:00Z"

test_case "empty input selects nothing"
OUT=$(run_select '[]' "sha-" 7 2 "$NOW")
assert_eq "no candidates" "[]" "$OUT"

test_case "never deletes a tag that doesn't match the ephemeral prefix"
OUT=$(run_select '[{"id":"latest","tags":["latest"],"updated_at":"2020-01-01T00:00:00Z"}]' "sha-" 7 2 "$NOW")
assert_eq "official tag protected" "[]" "$OUT"

test_case "never deletes an entry co-tagged with a non-ephemeral tag"
OUT=$(run_select '[{"id":"mixed","tags":["sha-99","1.2.3"],"updated_at":"2020-01-01T00:00:00Z"}]' "sha-" 7 2 "$NOW")
assert_eq "mixed-tag entry protected" "[]" "$OUT"

test_case "never deletes an untagged entry"
OUT=$(run_select '[{"id":"untagged","tags":[],"updated_at":"2020-01-01T00:00:00Z"}]' "sha-" 7 2 "$NOW")
assert_eq "untagged entry protected" "[]" "$OUT"

test_case "always keeps the keep_min most recent ephemeral entries regardless of age"
OUT=$(run_select '[{"id":"sha-old","tags":["sha-old"],"updated_at":"2020-01-01T00:00:00Z"}]' "sha-" 7 5 "$NOW")
assert_eq "below keep_min, kept even though ancient" "[]" "$OUT"

test_case "deletes ephemeral entries beyond keep_min once older than retention_days"
JSON='[
  {"id":"sha-5","tags":["sha-5"],"updated_at":"2026-01-09T00:00:00Z"},
  {"id":"sha-4","tags":["sha-4"],"updated_at":"2026-01-08T00:00:00Z"},
  {"id":"sha-3","tags":["sha-3"],"updated_at":"2026-01-02T00:00:00Z"},
  {"id":"sha-2","tags":["sha-2"],"updated_at":"2026-01-01T00:00:00Z"},
  {"id":"sha-1","tags":["sha-1"],"updated_at":"2025-12-01T00:00:00Z"}
]'
OUT=$(run_select "$JSON" "sha-" 7 2 "$NOW")
assert_eq "oldest three selected, two most recent kept" '["sha-3","sha-2","sha-1"]' "$OUT"

test_case "keeps entries beyond keep_min if still within the retention window"
JSON='[
  {"id":"sha-2","tags":["sha-2"],"updated_at":"2026-01-09T00:00:00Z"},
  {"id":"sha-1","tags":["sha-1"],"updated_at":"2026-01-08T00:00:00Z"}
]'
OUT=$(run_select "$JSON" "sha-" 7 1 "$NOW")
assert_eq "second entry recent enough to keep" "[]" "$OUT"

test_case "GHCR-shaped input (id = numeric version id) works the same way"
JSON='[
  {"id":"918273","tags":["sha-abc123"],"updated_at":"2025-12-01T00:00:00Z"},
  {"id":"918274","tags":["edge"],"updated_at":"2026-01-09T00:00:00Z"}
]'
OUT=$(run_select "$JSON" "sha-" 7 0 "$NOW")
assert_eq "only the sha-tagged version id is selected, edge protected" '["918273"]' "$OUT"

test_case "a custom ephemeral prefix only matches its own tags"
JSON='[
  {"id":"sha-abc","tags":["sha-abc"],"updated_at":"2025-12-01T00:00:00Z"},
  {"id":"build-123","tags":["build-123"],"updated_at":"2025-12-01T00:00:00Z"}
]'
OUT=$(run_select "$JSON" "build-" 7 0 "$NOW")
assert_eq "only build- prefixed entry selected" '["build-123"]' "$OUT"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
