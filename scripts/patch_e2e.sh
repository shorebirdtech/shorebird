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
# Usage: ./patch_e2e.sh <flutter-version|default>
#
# "default" releases with the Flutter version the CLI pins.

FLUTTER_VERSION=$1
if [[ "$FLUTTER_VERSION" == "default" ]]; then
    FLUTTER_VERSION_ARGS=()
else
    FLUTTER_VERSION_ARGS=(--flutter-version="$FLUTTER_VERSION")
fi

# How long to wait for an expected log line before failing.
WAIT_SECONDS=300

# Runs a command and waits for a line of its output to contain a pattern.
# Fails with the device log if the pattern does not appear within
# WAIT_SECONDS or the command's output ends first. The command keeps running
# after a match; callers stop it explicitly.
#
# Usage: wait_for_line <pattern> <command> [args...]
wait_for_line() {
    local pattern=$1
    shift
    # Tracing every log line comparison buries the rest of the job log.
    set +x
    local deadline=$((SECONDS + WAIT_SECONDS))
    local line status
    while ((SECONDS < deadline)); do
        # Under -e a bare failing read would exit before status is checked.
        IFS= read -r -t 10 line && status=0 || status=$?
        if ((status == 0)); then
            if [[ "$line" == *"$pattern"* ]]; then
                set -x
                return 0
            fi
        elif ((status <= 128)); then
            echo "❌ Output ended before '$pattern' was seen."
            dump_device_log
            exit 1
        fi
    done < <("$@")
    echo "❌ '$pattern' was not seen within ${WAIT_SECONDS}s."
    dump_device_log
    exit 1
}

dump_device_log() {
    echo "Device log (all buffers):"
    adb logcat -d -b all || true
}

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
echo "base_url: https://api-dev.shorebird.dev" >>shorebird.yaml

# Extract the app_id from the "shorebird.yaml"
APP_ID=$(cat shorebird.yaml | grep 'app_id:' | awk '{print $2}')

# Create Debug Keystore
# Android Studio creates this keystore by default, but we need to create it manually for CI.
# See https://github.com/google/bundletool/blob/69c3e0947bab350fbe7cbd9af03a77b0204d6dc8/src/main/java/com/android/tools/build/bundletool/commands/BuildApksCommand.java
keytool -genkey -v -keystore ~/.android/debug.keystore -keyalg RSA \
    -keysize 2048 -validity 10000 -alias AndroidDebugKey -storepass android -keypass android \
    -dname "CN=Android Debug,O=Android,C=US"

# Create a new release on Android
shorebird release android "${FLUTTER_VERSION_ARGS[@]}" --split-debug-info=./build/symbols -v

# Run the app on Android and ensure that the print statement is printed.
wait_for_line "I flutter : hello world" \
    shorebird preview --release-version 0.1.0+1 --app-id $APP_ID --platform android -v
adb kill-server
echo "✅ 'hello world' was printed"

# Replace lib/main.dart "hello world" to "hello shorebird"
sed -i 's/hello world/hello shorebird/g' lib/main.dart

echo "lib/main.dart is now:"
cat lib/main.dart

# Create a patch
shorebird patch android --release-version 0.1.0+1 --split-debug-info=./build/symbols -v

# Run the app on Android and ensure that the original print statement is printed.
wait_for_line "Patch 1 successfully" \
    shorebird preview --release-version 0.1.0+1 --app-id $APP_ID --platform android -v
# Kill the app so we can boot the patch
adb shell am force-stop com.example.e2e_test.e2e_test
echo "✅ Patch 1 successfully installed"

# Re-run the app, *not* using shorebird preview, as that installs the base release.
adb shell monkey -p com.example.e2e_test.e2e_test -c android.intent.category.LAUNCHER 1

# Re-run the app on Android and ensure that the new print statement is printed,
# tailing adb logs and printing the last 10 seconds of logs in case the
# "hello shorebird" statement was printed before entering the loop.
wait_for_line "I flutter : hello shorebird" adb logcat -T '10.0'
adb kill-server
echo "✅ 'hello shorebird' was printed"

echo "✅ All tests passed!"
exit 0
