#!/bin/bash -ex

# Tests release, patch and boot on Android end to end. It creates an empty
# Flutter app, initializes Shorebird, releases it, checks the release prints
# "hello world", patches it to print "hello shorebird", checks the patch
# downloads, then cold-starts the app and checks the patch runs.
#
# Usage: ./patch_e2e.sh [--cli <path|version>] [--avd <name>] [--org-id <id>]
#                       [<flutter-version|default>]
#
#   <flutter-version>  Flutter version to release with. "default" (or nothing)
#                      releases with the Flutter version the CLI pins. The
#                      test app is created with the `flutter` on PATH, so use
#                      one whose templates that version builds (CI installs
#                      the same version).
#   --cli <path>       Shorebird checkout to test (the directory holding
#                      bin/shorebird). Defaults to the checkout holding this
#                      script.
#   --cli <version>    A released CLI version, e.g. 1.4.0. Its tag is cloned
#                      once into ${XDG_CACHE_HOME:-~/.cache}/shorebird_patch_e2e/
#                      and reused. Its test app is created with that
#                      version's pinned Flutter, whose templates it can build.
#   --avd <name>       AVD to boot when no device is attached. Defaults to
#                      $SHOREBIRD_E2E_AVD, else the first AVD
#                      `emulator -list-avds` prints.
#   --org-id <id>      Organization to create the test app in. Defaults to
#                      $SHOREBIRD_E2E_ORG_ID; needed when the account can
#                      create apps in more than one (Shorebird E2E is 437 on
#                      dev).
#
# Device: an attached device or running emulator is used as is (set
# ANDROID_SERIAL to pick one of several). With none attached, the script boots
# the AVD headless (as emulator-5580, or on the port ANDROID_SERIAL=emulator-N
# names), waits for it to finish booting, and shuts it down on exit.
#
# Server: $SHOREBIRD_HOSTED_URL, default https://api-dev.shorebird.dev. The app
# the script creates there is deleted on exit, pass or fail.
#
# Pre-requisites: Flutter, the Android SDK with adb on PATH, Java, and a
# signed-in Shorebird account (or CI credentials) on that server.
#
# Older CLIs keep their login in a file this checkout's CLI migrates and
# deletes (init and cleanup run with it), so for --cli <version> set
# SHOREBIRD_TOKEN, from `shorebird login:ci` run with that version.
#
# Examples:
#   ./patch_e2e.sh                   # this checkout's CLI, its pinned Flutter
#   ./patch_e2e.sh 3.27.4            # release with Flutter 3.27.4
#   ./patch_e2e.sh --cli 1.4.0       # CLI 1.4.0 against the current server

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(dirname "$SCRIPT_DIR")

FLUTTER_VERSION=default
CLI=$REPO_ROOT
AVD=${SHOREBIRD_E2E_AVD:-}
ORG_ID=${SHOREBIRD_E2E_ORG_ID:-}
EMULATOR_PID=
while (($# > 0)); do
    if [[ "$1" == --cli || "$1" == --avd || "$1" == --org-id ]] && (($# < 2)); then
        echo "❌ $1 needs a value. See the usage at the top of $0."
        exit 64
    fi
    case $1 in
    --cli)
        CLI=$2
        shift 2
        ;;
    --avd)
        AVD=$2
        shift 2
        ;;
    --org-id)
        ORG_ID=$2
        shift 2
        ;;
    -*)
        echo "❌ Unknown option $1. See the usage at the top of $0."
        exit 64
        ;;
    *)
        FLUTTER_VERSION=$1
        shift
        ;;
    esac
done

if [[ "$FLUTTER_VERSION" == "default" ]]; then
    FLUTTER_VERSION_ARGS=()
else
    FLUTTER_VERSION_ARGS=(--flutter-version="$FLUTTER_VERSION")
fi
INIT_ARGS=()
if [[ -n "$ORG_ID" ]]; then
    INIT_ARGS=(--org-id="$ORG_ID")
fi

# How long to wait for an expected log line, or for a device to boot, before
# failing.
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

# Waits until the device reports sys.boot_completed. `adb wait-for-device`
# returns as soon as adb can see the device, well before the package manager
# can install anything.
wait_for_boot() {
    set +x
    local deadline=$((SECONDS + WAIT_SECONDS))
    until [[ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; do
        if [[ -n "$EMULATOR_PID" ]] && ! kill -0 "$EMULATOR_PID" 2>/dev/null; then
            echo "❌ The emulator exited while booting. Its log:"
            cat "$EMULATOR_LOG" || true
            exit 1
        fi
        if ((SECONDS >= deadline)); then
            echo "❌ The device did not finish booting within ${WAIT_SECONDS}s."
            adb devices -l || true
            exit 1
        fi
        sleep 2
    done
    set -x
}

has_device() {
    # A cold adb server can list a running emulator as offline at first.
    adb start-server
    if [[ -n "${ANDROID_SERIAL:-}" ]]; then
        [[ "$(adb -s "$ANDROID_SERIAL" get-state 2>/dev/null)" == "device" ]]
    else
        adb devices | grep -q $'\tdevice$'
    fi
}

# Boots $AVD headless on a port of our own, so the serial is known and later
# adb commands go to it.
start_emulator() {
    local sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}
    local emulator=$sdk/emulator/emulator
    if [[ ! -x "$emulator" ]]; then
        echo "❌ No device is attached and there is no emulator at $emulator."
        echo "Attach a device, or set ANDROID_HOME to an SDK with the emulator."
        exit 1
    fi
    if [[ -z "$AVD" ]]; then
        AVD=$("$emulator" -list-avds | head -n 1)
        if [[ -z "$AVD" ]]; then
            echo "❌ No device is attached and there are no AVDs to boot."
            echo "Create one in Android Studio or with avdmanager, or attach a device."
            exit 1
        fi
    fi
    local port=5580
    if [[ "${ANDROID_SERIAL:-}" =~ ^emulator-([0-9]+)$ ]]; then
        port=${BASH_REMATCH[1]}
    elif [[ -n "${ANDROID_SERIAL:-}" ]]; then
        echo "❌ ANDROID_SERIAL=$ANDROID_SERIAL is not attached."
        exit 1
    fi
    export ANDROID_SERIAL=emulator-$port
    EMULATOR_LOG="$TEMP_DIR/emulator.log"
    echo "No device attached; booting AVD '$AVD' as $ANDROID_SERIAL."
    "$emulator" -avd "$AVD" -port "$port" -no-window -no-audio -no-boot-anim \
        -no-snapshot-save >"$EMULATOR_LOG" 2>&1 &
    EMULATOR_PID=$!
    wait_for_boot
}

stop_emulator() {
    if [[ -n "$EMULATOR_PID" ]]; then
        echo "Shutting down the emulator this script started"
        adb emu kill >/dev/null 2>&1 || true
        local deadline=$((SECONDS + 30))
        while kill -0 "$EMULATOR_PID" 2>/dev/null && ((SECONDS < deadline)); do
            sleep 1
        done
        kill -9 "$EMULATOR_PID" 2>/dev/null || true
    fi
}

# Resolves --cli to a checkout directory: a path is used as is, a version is
# cloned at its tag once and reused.
resolve_cli() {
    if [[ -d "$CLI" ]]; then
        CLI_DIR=$(cd "$CLI" && pwd)
    elif [[ "$CLI" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        local tag=v${CLI#v}
        CLI_DIR=${XDG_CACHE_HOME:-$HOME/.cache}/shorebird_patch_e2e/cli-$tag
        if [[ ! -d "$CLI_DIR" ]]; then
            mkdir -p "$(dirname "$CLI_DIR")"
            rm -rf "$CLI_DIR.tmp"
            git clone --depth 1 --branch "$tag" \
                https://github.com/shorebirdtech/shorebird.git "$CLI_DIR.tmp"
            # Installs track the stable branch, and older CLIs read their
            # version and check for updates through it, failing on a detached
            # HEAD or a branch without an upstream.
            git -C "$CLI_DIR.tmp" remote set-branches origin stable
            git -C "$CLI_DIR.tmp" fetch --depth 1 origin stable
            git -C "$CLI_DIR.tmp" checkout -b stable --no-track
            git -C "$CLI_DIR.tmp" branch --set-upstream-to=origin/stable
            mv "$CLI_DIR.tmp" "$CLI_DIR"
        fi
    else
        echo "❌ --cli $CLI is neither a directory nor a version like 1.4.0."
        exit 64
    fi
    if [[ ! -x "$CLI_DIR/bin/shorebird" ]]; then
        echo "❌ $CLI_DIR has no bin/shorebird; --cli takes a Shorebird checkout."
        exit 64
    fi
}

# The environment this script exercises. This is the name the CLI itself reads
# (see ShorebirdEnv.hostedUri), and the e2e workflow already sets it per job, so
# take it from the environment when it is there and default to dev for local
# runs. `shorebird release` and `shorebird patch` pick it up from the
# environment or from shorebird.yaml below, and so does the cleanup trap's
# `shorebird api`.
export SHOREBIRD_HOSTED_URL="${SHOREBIRD_HOSTED_URL:-https://api-dev.shorebird.dev}"

# `shorebird init` mints a brand new app on every leg, and the nightly runs 30
# of them. Left alone the e2e account's app list grows by ~30 a night forever,
# and every `shorebird release` fetches that whole list up front -- by Aug 2026
# it was a 7.7MB response taking 10s under load, which saturated api-dev and
# made it shed requests with a 429. Delete the app this leg created, whether or
# not the test passed, so the list stays flat.
#
# There is no `shorebird apps delete` command, so this calls the API through
# `shorebird api`, which signs in the same way the commands above do. It uses
# this checkout's CLI, since an older CLI under test may not have `api`.
cleanup() {
    local status=$?
    if [[ -n "${APP_ID:-}" ]]; then
        echo "Deleting e2e app $APP_ID"
        "$REPO_ROOT/bin/shorebird" api -X DELETE "apps/$APP_ID" ||
            echo "⚠️  Failed to delete e2e app $APP_ID; it will need pruning."
    fi
    stop_emulator
    return $status
}
trap cleanup EXIT

resolve_cli
export PATH="$CLI_DIR/bin:$PATH"
shorebird --version

# Intentionally including a space in the path.
TEMP_DIR=$(mktemp -d -t 'shorebird workspace-XXXXX')

if ! has_device; then
    start_emulator
fi

cd "$TEMP_DIR"

# A released CLI's pinned Flutter may not build the templates a newer host
# Flutter writes, so create the app with that Flutter. `shorebird --version`
# above installed it.
CREATE_FLUTTER=flutter
if [[ "$FLUTTER_VERSION" == "default" && "$CLI_DIR" != "$REPO_ROOT" ]]; then
    PINNED_FLUTTER="$CLI_DIR/bin/cache/flutter/$(cat "$CLI_DIR/bin/internal/flutter.version")/bin/flutter"
    if [[ -x "$PINNED_FLUTTER" ]]; then
        CREATE_FLUTTER=$PINNED_FLUTTER
    fi
fi

# Create a new empty flutter project
"$CREATE_FLUTTER" create e2e_test --org com.example.e2e_test --empty --platforms android
cd e2e_test

# Replace the contents of "lib/main.dart" with a single print statement.
echo "void main() { print('hello world'); }" >lib/main.dart

# Initialize Shorebird. This uses this checkout's CLI, like the cleanup trap,
# so --org-id works when the CLI under test predates it. Release, preview and
# patch below use the CLI under test.
"$REPO_ROOT/bin/shorebird" init --force "${INIT_ARGS[@]}" -v

# Extract the app_id from the "shorebird.yaml" right away, so the cleanup trap
# deletes the app even if a later step fails.
APP_ID=$(cat shorebird.yaml | grep 'app_id:' | awk '{print $2}')

# Run Flutter & Shorebird doctor to ensure that the project is set up correctly.
flutter doctor --verbose
shorebird doctor --verbose

# Point to the development environment
echo "base_url: $SHOREBIRD_HOSTED_URL" >>shorebird.yaml

# Create Debug Keystore
# Android Studio creates this keystore by default, but we need to create it manually for CI.
# See https://github.com/google/bundletool/blob/69c3e0947bab350fbe7cbd9af03a77b0204d6dc8/src/main/java/com/android/tools/build/bundletool/commands/BuildApksCommand.java
if [[ ! -f ~/.android/debug.keystore ]]; then
    mkdir -p ~/.android
    keytool -genkey -v -keystore ~/.android/debug.keystore -keyalg RSA \
        -keysize 2048 -validity 10000 -alias AndroidDebugKey -storepass android -keypass android \
        -dname "CN=Android Debug,O=Android,C=US"
fi

# CLIs before --split-debug-info became a `shorebird` option (e.g. 1.4.0)
# take it as a flag forwarded to `flutter build`.
if shorebird release --help | grep -qE '^ +--split-debug-info'; then
    SPLIT_DEBUG_INFO_ARGS=(--split-debug-info=./build/symbols)
else
    SPLIT_DEBUG_INFO_ARGS=(-- --split-debug-info=./build/symbols)
fi

# Create a new release on Android
shorebird release android "${FLUTTER_VERSION_ARGS[@]}" -v "${SPLIT_DEBUG_INFO_ARGS[@]}"

# Run the app on Android and ensure that the print statement is printed.
wait_for_line "I flutter : hello world" \
    shorebird preview --release-version 0.1.0+1 --app-id "$APP_ID" --platform android -v
# Killing the adb server is what breaks `shorebird preview` out of its logcat
# tail. Wait for the device to come back so later adb commands don't race the
# restarted daemon and see it as "offline".
adb kill-server
wait_for_boot
echo "✅ 'hello world' was printed"

# Change the print statement to "hello shorebird". Rewritten rather than
# edited in place, since `sed -i` differs between GNU and BSD.
echo "void main() { print('hello shorebird'); }" >lib/main.dart

echo "lib/main.dart is now:"
cat lib/main.dart

# Create a patch
shorebird patch android --release-version 0.1.0+1 -v "${SPLIT_DEBUG_INFO_ARGS[@]}"

# Run the app on Android and wait for it to download and install the patch.
wait_for_line "Patch 1 successfully" \
    shorebird preview --release-version 0.1.0+1 --app-id "$APP_ID" --platform android -v
# Kill the app so we can boot the patch
adb shell am force-stop com.example.e2e_test.e2e_test
echo "✅ Patch 1 successfully installed"

# Note the device's clock before launching, so the log tail below starts at
# this launch and can't match a line an earlier run on the same device
# printed. logcat -T takes seconds since the epoch.
LAUNCHED_AT=$(adb shell date +%s | tr -d '\r')

# Re-run the app, *not* using shorebird preview, as that installs the base release.
adb shell monkey -p com.example.e2e_test.e2e_test -c android.intent.category.LAUNCHER 1

# Ensure that the patched print statement is printed.
wait_for_line "I flutter : hello shorebird" adb logcat -T "$LAUNCHED_AT.000"
adb kill-server
echo "✅ 'hello shorebird' was printed"

echo "✅ All tests passed!"
exit 0
