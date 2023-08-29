#!/bin/sh -e

# A script for computing combined coverage for all packages in the repo.
# This can be used for viewing coverage locally in your editor.

# This generates into ./coverage/lcov.info, which may not be the correct
# directory if you've opened a single package or a directory above 'shorebird'
# in your editor.

# Our GitHub actions build coverage and upload it to Codecov, so you
# don't need to run this script to see coverage on GitHub.
# https://app.codecov.io/gh/shorebirdtech/shorebird

dart pub global activate coverage
dart pub global activate combine_coverage

PACKAGES=$(ls -d packages/*)
echo $PACKAGES

for PACKAGE_DIR in $PACKAGES
do
    echo $PACKAGE_DIR
    cd $PACKAGE_DIR
    dart pub get
    dart test --coverage=coverage
    dart pub global run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info --packages=.dart_tool/package_config.json --report-on=lib --check-ignore
    cd ../..
done

dart pub global run combine_coverage --repo-path .