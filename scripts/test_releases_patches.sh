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

# ---------------------------------------------------------------------------
# releases list
# ---------------------------------------------------------------------------
echo "--- releases list ---"

$SHOREBIRD releases list --app-id "$APP_ID"
pass "releases list (human)"

OUT=$($SHOREBIRD releases list --app-id "$APP_ID" --json)
echo "$OUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['status'] == 'success', d
assert isinstance(d['data']['releases'], list), d
"
pass "releases list --json"

# ---------------------------------------------------------------------------
# releases info
# ---------------------------------------------------------------------------
echo "--- releases info ---"

$SHOREBIRD releases info --app-id "$APP_ID" --release-version "$RELEASE_VERSION"
pass "releases info (human)"

OUT=$($SHOREBIRD releases info --app-id "$APP_ID" --release-version "$RELEASE_VERSION" --json)
echo "$OUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['status'] == 'success', d
r = d['data']['release']
assert 'version' in r, r
assert 'platform_statuses' in r, r
"
pass "releases info --json"

# bad version returns error envelope
set +e
OUT=$($SHOREBIRD releases info --app-id "$APP_ID" --release-version "0.0.0+999" --json 2>/dev/null)
EXIT=$?
set -e
echo "$OUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['status'] == 'error', d
" || fail "releases info bad version should return error envelope"
[ "$EXIT" -ne 0 ] || fail "releases info bad version should exit non-zero"
pass "releases info bad version returns error envelope"

# ---------------------------------------------------------------------------
# patches list
# ---------------------------------------------------------------------------
echo "--- patches list ---"

$SHOREBIRD patches list --app-id "$APP_ID" --release-version "$RELEASE_VERSION"
pass "patches list (human)"

OUT=$($SHOREBIRD patches list --app-id "$APP_ID" --release-version "$RELEASE_VERSION" --json)
echo "$OUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['status'] == 'success', d
assert isinstance(d['data']['patches'], list), d
"
pass "patches list --json"

# ---------------------------------------------------------------------------
# patches info
# ---------------------------------------------------------------------------
echo "--- patches info ---"

$SHOREBIRD patches info --app-id "$APP_ID" --release-version "$RELEASE_VERSION" --patch-number "$PATCH_NUMBER"
pass "patches info (human)"

OUT=$($SHOREBIRD patches info --app-id "$APP_ID" --release-version "$RELEASE_VERSION" --patch-number "$PATCH_NUMBER" --json)
echo "$OUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['status'] == 'success', d
p = d['data']['patch']
assert 'number' in p, p
assert 'is_rolled_back' in p, p
"
pass "patches info --json"

# bad patch number returns error envelope
set +e
OUT=$($SHOREBIRD patches info --app-id "$APP_ID" --release-version "$RELEASE_VERSION" --patch-number 99999 --json 2>/dev/null)
EXIT=$?
set -e
echo "$OUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['status'] == 'error', d
assert d['error']['code'] == 'usage_error', d
" || fail "patches info bad patch number should return usage_error envelope"
[ "$EXIT" -ne 0 ] || fail "patches info bad patch number should exit non-zero"
pass "patches info bad patch number returns error envelope"

echo ""
echo "✅ All smoke tests passed."
