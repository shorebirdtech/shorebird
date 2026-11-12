#!/bin/bash -e

# cspell:words cmdline sdkmanager Seekable

# Installs Android SDK packages with sdkmanager, retrying a failed download.
#
# An install normally takes 20-30 seconds. Its download from dl.google.com
# has failed e2e jobs that tested nothing: a corrupt NDK zip ("Error reading
# Zip content from a SeekableByteChannel", runs 41553186726 and 43237646183)
# and one that hung until the step timed out (run 42728409530). Each attempt
# gets a deadline, and a failed attempt's partial download is deleted before
# the next one, since sdkmanager can resume an interrupted download from it
# and read the same bad bytes again.
#
# Usage: ./install_android_sdk_packages.sh <package> [package...]
# e.g. ./install_android_sdk_packages.sh "ndk;28.2.13676358" "cmake;3.22.1"

if [[ -z "$ANDROID_HOME" ]]; then
    echo "❌ ANDROID_HOME is not set."
    exit 1
fi
if [[ $# -eq 0 ]]; then
    echo "❌ Usage: $0 <package> [package...]"
    exit 1
fi

sdkmanager="${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager"
attempts=3
# About six times a normal install.
deadline=3m

for attempt in $(seq 1 "$attempts"); do
    status=0
    timeout --kill-after=10s "$deadline" "$sdkmanager" --install "$@" ||
        status=$?
    if [[ $status -eq 0 ]]; then
        exit 0
    fi
    if [[ $status -eq 124 ]]; then
        echo "⚠️ sdkmanager timed out after $deadline (attempt $attempt of $attempts)."
    else
        echo "⚠️ sdkmanager exited $status (attempt $attempt of $attempts)."
    fi
    # Where sdkmanager keeps downloads and unpacks them (which one depends on
    # its version); a package moves into place only once unpacked.
    rm -rf "${ANDROID_HOME}/.downloadIntermediates" "${ANDROID_HOME}/.temp" \
        "${HOME}/.android/cache"
done

echo "❌ Could not install $* after $attempts attempts."
exit 1
