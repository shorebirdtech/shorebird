#!/bin/bash
set -euo pipefail

# Checks that macOS patches still apply after the app is re-signed following
# `shorebird release`. Re-signing is what Developer ID notarization flows and
# Mac App Store submission do to the binary, and it is the failure in
# https://github.com/shorebirdtech/shorebird/issues/3223.
#
# The script creates one release and one patch, then runs the patch against
# several copies of the released app, each signed differently:
#
#   control       Ad-hoc re-sign. Leaves App.framework/App byte-identical, so
#                 the patch must apply. Guards against the harness itself
#                 being broken.
#   developer-id  "Developer ID Application" identity with hardened runtime,
#                 as for direct (notarized) distribution.
#   app-store     "Apple Distribution" (or "3rd Party Mac Developer
#                 Application") identity, sandboxed, as for the Mac App Store.
#                 Stands in for Apple re-signing the app after submission.
#
# Each variant is launched twice. The first launch downloads the patch; the
# second must print the patched marker. A variant fails if the updater
# reports a failure, the patch never installs, or the marker is unpatched.
# The script exits non-zero if any variant fails.
#
# This is a local harness, not run in CI. It launches real (headful) app
# windows.
#
# Pre-requisites:
# - macOS, with Flutter and Shorebird installed and `shorebird login` done.
# - Code signing identities for the developer-id and app-store variants in the
#   keychain (see `security find-identity -v -p codesigning`).
#
# Environment:
# - SHOREBIRD: the CLI to run (default: shorebird). Point at a checkout's
#   bin/shorebird to test unreleased CLI changes.
# - SHOREBIRD_FLAGS: extra top-level flags for release and patch, e.g.
#   "--local-engine-src-path=... --local-engine=... --local-engine-host=...".
# - SHOREBIRD_ORG_ID: organization for the temporary app. Required if the
#   account belongs to more than one organization.
# - SHOREBIRD_HOSTED_URL: API to use (default: the CLI's default).
# - DEVELOPER_ID_IDENTITY, APP_STORE_IDENTITY: override the identities found
#   in the keychain.
# - KEEP_WORKSPACE=1: keep the temporary project and app copies.
#
# Usage: ./macos_resign_e2e.sh

# cspell:words headful libexec sandboxed sbresign

if [[ "$(uname)" != "Darwin" ]]; then
    echo "❌ This script only runs on macOS."
    exit 1
fi

SHOREBIRD="${SHOREBIRD:-shorebird}"
read -r -a SHOREBIRD_FLAGS_ARRAY <<<"${SHOREBIRD_FLAGS:-}"

# How long to wait for the updater to install the patch, or for the app to
# print its marker.
WAIT_SECONDS=120

find_identity() {
    security find-identity -v -p codesigning |
        grep -o "\"$1[^\"]*\"" | head -1 | tr -d '"' || true
}

DEVELOPER_ID_IDENTITY="${DEVELOPER_ID_IDENTITY:-$(find_identity 'Developer ID Application: ')}"
APP_STORE_IDENTITY="${APP_STORE_IDENTITY:-$(find_identity 'Apple Distribution: ')}"
APP_STORE_IDENTITY="${APP_STORE_IDENTITY:-$(find_identity '3rd Party Mac Developer Application: ')}"
if [[ -z "$DEVELOPER_ID_IDENTITY" || -z "$APP_STORE_IDENTITY" ]]; then
    echo "❌ Missing code signing identities:"
    echo "   developer-id: ${DEVELOPER_ID_IDENTITY:-<none>}"
    echo "   app-store:    ${APP_STORE_IDENTITY:-<none>}"
    echo "Set DEVELOPER_ID_IDENTITY / APP_STORE_IDENTITY, or add the identities."
    exit 1
fi

VARIANTS=(control developer-id app-store)

# Unique per run, so every variant gets a fresh sandbox container (which holds
# the updater's state) and runs never see each other's patches.
RUN_ID=$(date +%s)
BUNDLE_ID_BASE="com.example.sbresign$RUN_ID"
PROJECT_NAME=macos_resign_e2e

# Intentionally including a space in the path.
WORKSPACE=$(mktemp -d -t 'shorebird workspace-XXXXX')

APP_ID=""
cleanup() {
    local status=$?
    if [[ -n "$APP_ID" ]]; then
        echo "Deleting app $APP_ID"
        "$SHOREBIRD" apps delete --app-id "$APP_ID" \
            --confirm-name "$PROJECT_NAME" ||
            echo "⚠️  Failed to delete app $APP_ID; delete it by hand."
    fi
    # macOS does not let us delete a sandbox container itself, only its
    # contents, so each run leaves a small empty container per variant.
    for variant in "${VARIANTS[@]}"; do
        rm -rf "$HOME/Library/Containers/$BUNDLE_ID_BASE.$variant/Data/Library" \
            2>/dev/null || true
    done
    if [[ "${KEEP_WORKSPACE:-}" == "1" ]]; then
        echo "Workspace kept at: $WORKSPACE"
    else
        rm -rf "$WORKSPACE"
    fi
    return "$status"
}
trap cleanup EXIT

cd "$WORKSPACE"
flutter create "$PROJECT_NAME" --org "$BUNDLE_ID_BASE" --empty --platforms macos
cd "$PROJECT_NAME"

echo "void main() { print('MARKER=base'); }" >lib/main.dart

INIT_ARGS=(--force --display-name "$PROJECT_NAME")
if [[ -n "${SHOREBIRD_ORG_ID:-}" ]]; then
    INIT_ARGS+=(--organization-id "$SHOREBIRD_ORG_ID")
fi
"$SHOREBIRD" init "${INIT_ARGS[@]}"
APP_ID=$(grep 'app_id:' shorebird.yaml | awk '{print $2}')
if [[ -n "${SHOREBIRD_HOSTED_URL:-}" ]]; then
    echo "base_url: $SHOREBIRD_HOSTED_URL" >>shorebird.yaml
fi

CI=1 "$SHOREBIRD" ${SHOREBIRD_FLAGS_ARRAY[@]+"${SHOREBIRD_FLAGS_ARRAY[@]}"} release macos --build-number 1
RELEASE_VERSION=0.1.0+1
BUILT_APP="build/macos/Build/Products/Release/$PROJECT_NAME.app"
BINARY_NAME=$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' \
    "$BUILT_APP/Contents/Info.plist")

app_binary_hash() {
    shasum -a 256 "$1/Contents/Frameworks/App.framework/App" | awk '{print $1}'
}
RELEASED_HASH=$(app_binary_hash "$BUILT_APP")

# Copy the released app once per variant, give each its own bundle id (so its
# own container), and re-sign it. Info.plist is outside App.framework, so
# changing it does not touch the binary the patch is diffed against.
make_variant() {
    local variant=$1
    local app="$WORKSPACE/$variant.app"
    ditto "$BUILT_APP" "$app"
    /usr/libexec/PlistBuddy -c "Set CFBundleIdentifier $BUNDLE_ID_BASE.$variant" \
        "$app/Contents/Info.plist"
    local sign_args=(--force --deep --preserve-metadata=entitlements --timestamp=none)
    case $variant in
    control) sign_args+=(-s -) ;;
    developer-id) sign_args+=(-o runtime -s "$DEVELOPER_ID_IDENTITY") ;;
    app-store) sign_args+=(-s "$APP_STORE_IDENTITY") ;;
    esac
    codesign "${sign_args[@]}" "$app"

    # Sanity-check that each variant exercises what it claims to.
    local hash
    hash=$(app_binary_hash "$app")
    if [[ "$variant" == "control" && "$hash" != "$RELEASED_HASH" ]]; then
        echo "❌ Harness error: control re-sign changed App.framework/App."
        exit 1
    fi
    if [[ "$variant" != "control" && "$hash" == "$RELEASED_HASH" ]]; then
        echo "❌ Harness error: $variant re-sign left App.framework/App unchanged."
        exit 1
    fi
}
for variant in "${VARIANTS[@]}"; do
    make_variant "$variant"
done

sed -i '' 's/MARKER=base/MARKER=patched/' lib/main.dart
CI=1 "$SHOREBIRD" ${SHOREBIRD_FLAGS_ARRAY[@]+"${SHOREBIRD_FLAGS_ARRAY[@]}"} patch macos \
    --release-version "$RELEASE_VERSION"

APP_PID=""
launch() {
    "$1/Contents/MacOS/$BINARY_NAME" >"$2" 2>&1 &
    APP_PID=$!
}
stop_app() {
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
}

# Prints "installed", "failed: <message>", "exited" or "timeout".
wait_for_install() {
    local state_dir=$1
    local deadline=$((SECONDS + WAIT_SECONDS))
    while ((SECONDS < deadline)); do
        if grep -q '"next_boot_patch": *1' "$state_dir/pointers.json" 2>/dev/null; then
            echo installed
            return
        fi
        if grep -q '__patch_update_failure__' "$state_dir/state.json" 2>/dev/null; then
            echo "failed: $(grep -o '"message": *"[^"]*"' "$state_dir/state.json" | head -1)"
            return
        fi
        if ! kill -0 "$APP_PID" 2>/dev/null; then
            echo exited
            return
        fi
        sleep 1
    done
    echo timeout
}

# Prints the MARKER value the app printed, "exited" or "timeout".
wait_for_marker() {
    local log=$1
    local deadline=$((SECONDS + WAIT_SECONDS))
    while ((SECONDS < deadline)); do
        if grep -q 'flutter: MARKER=' "$log"; then
            grep -o 'flutter: MARKER=[a-z]*' "$log" | head -1 | cut -d= -f2
            return
        fi
        if ! kill -0 "$APP_PID" 2>/dev/null; then
            echo exited
            return
        fi
        sleep 1
    done
    echo timeout
}

FAILED=0
RESULTS=()
for variant in "${VARIANTS[@]}"; do
    echo "▶️  $variant"
    app="$WORKSPACE/$variant.app"
    state_dir="$HOME/Library/Containers/$BUNDLE_ID_BASE.$variant/Data/Library/Application Support/shorebird/shorebird_updater/$APP_ID"

    launch "$app" "$WORKSPACE/$variant-1.log"
    install=$(wait_for_install "$state_dir")
    stop_app

    marker="-"
    if [[ "$install" == installed ]]; then
        launch "$app" "$WORKSPACE/$variant-2.log"
        marker=$(wait_for_marker "$WORKSPACE/$variant-2.log")
        stop_app
    fi

    if [[ "$install" == installed && "$marker" == patched ]]; then
        RESULTS+=("✅ $variant: patch installed and booted")
    else
        FAILED=1
        RESULTS+=("❌ $variant: install=$install, second launch marker=$marker")
        echo "First launch log ($variant):"
        cat "$WORKSPACE/$variant-1.log"
    fi
done

echo
echo "Results (release $RELEASE_VERSION, app $APP_ID):"
printf '  %s\n' "${RESULTS[@]}"
exit $FAILED
