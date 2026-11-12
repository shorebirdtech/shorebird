#!/bin/bash -e

# cspell:words cmdline sdkmanager Seekable

# Installs Android SDK packages with sdkmanager, retrying a failed download.
#
# An install normally takes 20-30 seconds. Its download from dl.google.com
# has failed e2e jobs that tested nothing: a corrupt NDK zip ("Error reading
# Zip content from a SeekableByteChannel", runs 41553186726 and 43237646183),
# and a download that stalled until the step timed out (run 42728409530, whose
# log stops at "Loading package information..."). e2e.yaml caches the NDK, so this downloads only
# on a cache miss. Each attempt gets a deadline, and a failed attempt's
# scratch files (partial downloads, unpacked pieces) are deleted, so the next
# one starts clean.
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
# The slowest of 235 successful installs took 207 seconds.
deadline=5m

for attempt in $(seq 1 "$attempts"); do
    status=0
    timeout --kill-after=10s "$deadline" "$sdkmanager" --install "$@" ||
        status=$?
    if [[ $status -eq 0 ]]; then
        exit 0
    fi
    # 124 from the deadline, 137 if it then had to be killed.
    if [[ $status -eq 124 || $status -eq 137 ]]; then
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
