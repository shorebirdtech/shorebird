#!/bin/bash
# Smoke-tests for `shorebird releases` and `shorebird patches` commands.
# Runs against a real app — requires a valid APP_ID and RELEASE_VERSION with
# at least one patch.
#
# Usage:
#   ./test_releases_patches.sh <app-id> <release-version> <patch-number>
#
# Example:
#   ./test_releases_patches.sh my-app-id 1.0.0+1 1

set -euo pipefail

# Use SHOREBIRD env var to override the binary (e.g. for dev builds):
#   SHOREBIRD="dart run packages/shorebird_cli/bin/shorebird.dart" ./scripts/test_releases_patches.sh ...
SHOREBIRD="${SHOREBIRD:-shorebird}"

APP_ID="${1:?Usage: $0 <app-id> <release-version> <patch-number>}"
RELEASE_VERSION="${2:?Usage: $0 <app-id> <release-version> <patch-number>}"
PATCH_NUMBER="${3:?Usage: $0 <app-id> <release-version> <patch-number>}"

pass() { echo "✅ $1"; }
fail() { echo "❌ $1"; exit 1; }

assert_json_success() {
  echo "$1" | jq -e '.status == "success"' > /dev/null || fail "$2: expected status=success"
}

assert_json_error() {
  local code="${3:-}"
  echo "$1" | jq -e '.status == "error"' > /dev/null || fail "$2: expected status=error"
  if [ -n "$code" ]; then
    echo "$1" | jq -e --arg c "$code" '.error.code == $c' > /dev/null || fail "$2: expected error.code=$code"
  fi
}

# ---------------------------------------------------------------------------
# releases list
# ---------------------------------------------------------------------------
echo "--- releases list ---"

$SHOREBIRD releases list --app-id "$APP_ID"
pass "releases list (human)"

OUT=$($SHOREBIRD releases list --app-id "$APP_ID" --json 2>/dev/null)
echo "$OUT" | jq .
assert_json_success "$OUT" "releases list"
echo "$OUT" | jq -e '.data.releases | length > 0' > /dev/null || fail "releases list: expected at least one release"
pass "releases list --json"

# bad app-id returns error envelope
set +e
OUT=$($SHOREBIRD releases list --app-id "00000000-0000-0000-0000-000000000000" --json 2>/dev/null)
EXIT=$?
set -e
echo "$OUT" | jq .
assert_json_error "$OUT" "releases list bad app-id"
[ "$EXIT" -ne 0 ] || fail "releases list bad app-id should exit non-zero"
pass "releases list bad app-id returns error envelope"

# ---------------------------------------------------------------------------
# releases info
# ---------------------------------------------------------------------------
echo "--- releases info ---"

$SHOREBIRD releases info --app-id "$APP_ID" --release-version "$RELEASE_VERSION"
pass "releases info (human)"

OUT=$($SHOREBIRD releases info --app-id "$APP_ID" --release-version "$RELEASE_VERSION" --json 2>/dev/null)
echo "$OUT" | jq .
assert_json_success "$OUT" "releases info"
echo "$OUT" | jq -e '.data.release.version' > /dev/null || fail "releases info: missing .data.release.version"
echo "$OUT" | jq -e '.data.release.platform_statuses' > /dev/null || fail "releases info: missing .data.release.platform_statuses"
pass "releases info --json"

# bad release version returns error envelope
set +e
OUT=$($SHOREBIRD releases info --app-id "$APP_ID" --release-version "0.0.0+999" --json 2>/dev/null)
EXIT=$?
set -e
echo "$OUT" | jq .
assert_json_error "$OUT" "releases info bad version"
[ "$EXIT" -ne 0 ] || fail "releases info bad version should exit non-zero"
pass "releases info bad version returns error envelope"

# ---------------------------------------------------------------------------
# patches list
# ---------------------------------------------------------------------------
echo "--- patches list ---"

$SHOREBIRD patches list --app-id "$APP_ID" --release-version "$RELEASE_VERSION"
pass "patches list (human)"

OUT=$($SHOREBIRD patches list --app-id "$APP_ID" --release-version "$RELEASE_VERSION" --json 2>/dev/null)
echo "$OUT" | jq .
assert_json_success "$OUT" "patches list"
echo "$OUT" | jq -e '.data.patches | type == "array"' > /dev/null || fail "patches list: .data.patches is not an array"
pass "patches list --json"

# bad release version returns error envelope
set +e
OUT=$($SHOREBIRD patches list --app-id "$APP_ID" --release-version "0.0.0+999" --json 2>/dev/null)
EXIT=$?
set -e
echo "$OUT" | jq .
assert_json_error "$OUT" "patches list bad release version"
[ "$EXIT" -ne 0 ] || fail "patches list bad release version should exit non-zero"
pass "patches list bad release version returns error envelope"

# ---------------------------------------------------------------------------
# patches info
# ---------------------------------------------------------------------------
echo "--- patches info ---"

$SHOREBIRD patches info --app-id "$APP_ID" --release-version "$RELEASE_VERSION" --patch-number "$PATCH_NUMBER"
pass "patches info (human)"

OUT=$($SHOREBIRD patches info --app-id "$APP_ID" --release-version "$RELEASE_VERSION" --patch-number "$PATCH_NUMBER" --json 2>/dev/null)
echo "$OUT" | jq .
assert_json_success "$OUT" "patches info"
echo "$OUT" | jq -e '.data.patch.number' > /dev/null || fail "patches info: missing .data.patch.number"
echo "$OUT" | jq -e '.data.patch | has("is_rolled_back")' > /dev/null || fail "patches info: missing .data.patch.is_rolled_back"
pass "patches info --json"

# bad patch number returns usage_error envelope
set +e
OUT=$($SHOREBIRD patches info --app-id "$APP_ID" --release-version "$RELEASE_VERSION" --patch-number 99999 --json 2>/dev/null)
EXIT=$?
set -e
echo "$OUT" | jq .
assert_json_error "$OUT" "patches info bad patch number" "usage_error"
[ "$EXIT" -ne 0 ] || fail "patches info bad patch number should exit non-zero"
pass "patches info bad patch number returns usage_error envelope"

# bad release version returns error envelope
set +e
OUT=$($SHOREBIRD patches info --app-id "$APP_ID" --release-version "0.0.0+999" --patch-number "$PATCH_NUMBER" --json 2>/dev/null)
EXIT=$?
set -e
echo "$OUT" | jq .
assert_json_error "$OUT" "patches info bad release version"
[ "$EXIT" -ne 0 ] || fail "patches info bad release version should exit non-zero"
pass "patches info bad release version returns error envelope"

echo ""
echo "✅ All smoke tests passed."
