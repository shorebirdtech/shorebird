#!/bin/sh -e

# A script for upgrading dependencies for all packages in the monorepo.
# Using a hard-coded list of packages for now, but could be improved to
# automatically find all packages in the monorepo.
PACKAGES='dex redis_client scoped_deps shorebird_build_trace shorebird_ci shorebird_cli shorebird_code_push_client shorebird_code_push_protocol'

for PACKAGE_DIR in $PACKAGES
do
    echo $PACKAGE_DIR
    cd packages/$PACKAGE_DIR
    dart pub upgrade
    cd ../..
done
