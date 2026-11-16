#!/bin/bash -e

# cspell:words sdkmanager

# Runs a command and fails if it installed any Android SDK package.
#
# CI pre-installs the SDK packages a build needs, so a download during the
# build itself means a Flutter or AGP change now needs a package the workflow
# doesn't install. A mid-build download has failed an e2e run before ("Error on
# ZipFile unknown archive"), so this turns that change into a failure that
# names the package instead.
#
# Usage: ./no_android_sdk_downloads.sh <command> [args...]

if [[ -z "$ANDROID_HOME" ]]; then
    echo "❌ ANDROID_HOME is not set."
    exit 1
fi

# Every installed package has a package.xml at its root, e.g.
# ndk/28.2.13676358/package.xml. Printed in sdkmanager's form,
# e.g. ndk;28.2.13676358.
list_packages() {
    (cd "$ANDROID_HOME" && find . -maxdepth 3 -name package.xml) |
        sed -e 's|^\./||' -e 's|/package\.xml$||' -e 's|/|;|g' | sort
}

before=$(list_packages)
status=0
# In the background, so a cancelled job's SIGTERM or SIGINT, which the runner
# sends only to this shell, reaches the command too and it can clean up (the
# e2e scripts delete the app they made on the server).
"$@" &
child=$!
trap 'kill -TERM "$child" 2>/dev/null' TERM INT
# A trapped signal ends `wait` early; wait again for the command to finish.
wait "$child" || status=$?
while kill -0 "$child" 2>/dev/null; do
    wait "$child" || status=$?
done
added=$(comm -13 <(echo "$before") <(list_packages))

if [[ -n "$added" ]]; then
    echo "❌ The command downloaded Android SDK packages:"
    echo "$added" | sed 's/^/  /'
    echo "Pre-install them in the workflow (android-packages in e2e.yaml)."
    exit 1
fi
exit $status
