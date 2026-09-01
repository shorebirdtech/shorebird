#!/bin/bash -ex

# This script tests the patching functionality of Shorebird.
# It creates a new empty, flutter project, initializes Shorebird,
# creates a new release, patches the release, and then ensures
# that the patch was applied correctly.
#
# Pre-requisites:
# - Flutter must be installed.
# - Android SDK must be installed.
# - ADB must be installed and be part of PATH.
# - Android emulator must be running.
# - Shorebird must be installed.
#
# Usage: ./patch_e2e.sh <flutter-version>

FLUTTER_VERSION=$1

# The environment this script exercises. `shorebird release` and `shorebird
# patch` pick this up from shorebird.yaml below; the cleanup trap calls the API
# directly and needs it too.
API_BASE_URL="https://api-dev.shorebird.dev"

# `shorebird init` mints a brand new app on every leg, and the nightly runs 30
# of them. Left alone the e2e account's app list grows by ~30 a night forever,
# and every `shorebird release` fetches that whole list up front -- by Aug 2026
# it was a 7.7MB response taking 10s under load, which saturated api-dev and
# made it shed requests with a 429. Delete the app this leg created, whether or
# not the test passed, so the list stays flat.
#
# There is no `shorebird apps delete` command, so this goes straight to the API.
# The x-version value must satisfy the server's `supportedClientVersions`; it is
# the same value the CLI sends, from
# packages/shorebird_code_push_client/lib/src/version.dart.
cleanup_app() {
    local status=$?
    if [[ -n "${APP_ID:-}" ]]; then
        echo "Deleting e2e app $APP_ID"
        curl --silent --show-error --fail-with-body -X DELETE \
            -H "Authorization: Bearer $SHOREBIRD_TOKEN" \
            -H "x-version: 0.9.0+1" \
            "$API_BASE_URL/api/v1/apps/$APP_ID" ||
            echo "⚠️  Failed to delete e2e app $APP_ID; it will need pruning."
    fi
    return $status
}
trap cleanup_app EXIT

# Intentionally including a space in the path.
TEMP_DIR=$(mktemp -d -t 'shorebird workspace-XXXXX')
cd "$TEMP_DIR"

# Create a new empty flutter project
flutter create e2e_test --org com.example.e2e_test --empty --platforms android
cd e2e_test

# Replace the contents of "lib/main.dart" with a single print statement.
echo "void main() { print('hello world'); }" >lib/main.dart

# Initialize Shorebird
shorebird init --force -v

# Run Flutter & Shorebird doctor to ensure that the project is set up correctly.
flutter doctor --verbose
shorebird doctor --verbose

# Point to the development environment
echo "base_url: $API_BASE_URL" >>shorebird.yaml

# Extract the app_id from the "shorebird.yaml"
APP_ID=$(cat shorebird.yaml | grep 'app_id:' | awk '{print $2}')

# Create Debug Keystore
# Android Studio creates this keystore by default, but we need to create it manually for CI.
# See https://github.com/google/bundletool/blob/69c3e0947bab350fbe7cbd9af03a77b0204d6dc8/src/main/java/com/android/tools/build/bundletool/commands/BuildApksCommand.java
keytool -genkey -v -keystore ~/.android/debug.keystore -keyalg RSA \
    -keysize 2048 -validity 10000 -alias AndroidDebugKey -storepass android -keypass android \
    -dname "CN=Android Debug,O=Android,C=US"

# Create a new release on Android
shorebird release android --flutter-version=$FLUTTER_VERSION --split-debug-info=./build/symbols -v

# Run the app on Android and ensure that the print statement is printed.
# `shorebird preview` runs in a process substitution, so its exit code is lost:
# if it fails (a 5xx from the API, say) the loop simply ends and the script
# would otherwise carry on and fail later with an unrelated error. Track
# whether the marker was seen and fail here instead.
saw_hello_world=0
while IFS= read line; do
    if [[ "$line" == *"I flutter : hello world"* ]]; then
        # Killing the adb server is what breaks `shorebird preview` out of its
        # logcat tail. Wait for the device to come back so later adb commands
        # don't race the restarted daemon and see it as "offline".
        adb kill-server
        adb wait-for-device
        saw_hello_world=1
        echo "✅ 'hello world' was printed"
        break
    fi
done < <(shorebird preview --release-version 0.1.0+1 --app-id $APP_ID --platform android -v)

if [[ "$saw_hello_world" != "1" ]]; then
    echo "❌ 'shorebird preview' never printed 'hello world' (see its output above)"
    exit 1
fi

# Replace lib/main.dart "hello world" to "hello shorebird"
sed -i 's/hello world/hello shorebird/g' lib/main.dart

echo "lib/main.dart is now:"
cat lib/main.dart

# Create a patch
shorebird patch android --release-version 0.1.0+1 --split-debug-info=./build/symbols -v

# Run the app on Android and ensure that the original print statement is printed.
saw_patch_installed=0
while IFS= read line; do
    if [[ "$line" == *"Patch 1 successfully"* ]]; then
        # Kill the app so we can boot the patch
        adb shell am force-stop com.example.e2e_test.e2e_test
        saw_patch_installed=1
        echo "✅ Patch 1 successfully installed"
        break
    fi
done < <(shorebird preview --release-version 0.1.0+1 --app-id $APP_ID --platform android -v)

if [[ "$saw_patch_installed" != "1" ]]; then
    echo "❌ 'shorebird preview' never installed patch 1 (see its output above)"
    exit 1
fi

# Re-run the app, *not* using shorebird preview, as that installs the base release.
adb shell monkey -p com.example.e2e_test.e2e_test -c android.intent.category.LAUNCHER 1

# Re-run the app on Android and ensure that the new print statement is printed,
# tailing adb logs and printing the last 10 seconds of logs in case the
# "hello shorebird" statement was printed before entering the loop.
# `adb logcat` never exits on its own, so bound the wait rather than letting the
# job burn its whole timeout when the patch didn't take.
saw_hello_shorebird=0
while IFS= read line; do
    if [[ "$line" == *"I flutter : hello shorebird"* ]]; then
        adb kill-server
        saw_hello_shorebird=1
        echo "✅ 'hello shorebird' was printed"
        break
    fi
done < <(timeout 120 adb logcat -T '10.0')

if [[ "$saw_hello_shorebird" != "1" ]]; then
    echo "❌ 'hello shorebird' was never printed; the patch did not boot"
    exit 1
fi

echo "✅ All tests passed!"
exit 0
