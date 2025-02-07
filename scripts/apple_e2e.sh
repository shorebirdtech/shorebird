#!/bin/bash -e -x

# Validates that iOS release and patch commands work as expected.
# This needs to be run locally on a machine with an iOS device attached.

rm -rf shorebird_temp
flutter create shorebird_temp --empty --platforms ios,macos
cd shorebird_temp
shorebird init -f
CI=1 shorebird release --platforms ios,macos
sed -i .orig 's/Hello World/Hello Shorebird/g' lib/main.dart
CI=1 shorebird patch --platforms ios,macos --release-version latest

shorebird preview --release-version 0.1.0+0.1.0 --platform ios > /dev/null &
shorebird preview --release-version 0.1.0+0.1.0 --platform macos > /dev/null &

echo "Once the patch is installed, kill the app and verify the 'Hello world! has been replaced by 'Hello shorebird'"