#!/bin/sh -e

# A script for upgrading dependencies for all packages in the monorepo.
# Using a hard-coded list of packages for now, but could be improved to
# automatically find all packages in the monorepo.
PACKAGES='artifact_proxy discord_gcp_alerts jwt redis_client scoped shorebird_cli shorebird_code_push_client shorebird_code_push_protocol'

for PACKAGE_DIR in $PACKAGES
do
    echo $PACKAGE_DIR
    cd packages/$PACKAGE_DIR
    dart pub upgrade
    cd ../..
done
