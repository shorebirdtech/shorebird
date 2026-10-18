#!/bin/bash -e
# cspell:words bundletool shasum

# Pins the CLI to a bundletool release: rewrites BundleToolArtifact.version
# and BundleToolArtifact.sha256 in packages/shorebird_cli/lib/src/cache.dart.
#
# Usage: scripts/update_bundletool.sh [<version>]
#
# With no version, uses the latest release of google/bundletool. Prints the
# pinned version. Needs curl, and gh only when no version is given.

cd "$(dirname "$0")/.."
CACHE_DART=packages/shorebird_cli/lib/src/cache.dart

VERSION="$1"
if [ -z "$VERSION" ]; then
  VERSION=$(gh api repos/google/bundletool/releases/latest --jq .tag_name)
fi

CURRENT=$(sed -n "s/^  static const version = '\(.*\)';$/\1/p" "$CACHE_DART")
if [ -z "$CURRENT" ]; then
  echo "Could not find BundleToolArtifact.version in $CACHE_DART" >&2
  exit 1
fi
if [ "$CURRENT" = "$VERSION" ]; then
  echo "bundletool is already at $VERSION" >&2
  echo "$VERSION"
  exit 0
fi

URL="https://github.com/google/bundletool/releases/download/$VERSION/bundletool-all-$VERSION.jar"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
echo "Downloading $URL" >&2
curl --fail --silent --show-error --location --output "$TMP/bundletool.jar" "$URL"
SHA256=$(shasum --algorithm 256 "$TMP/bundletool.jar" | cut -d' ' -f1)

# The checksum sits on the line after `static const sha256 =`.
sed -i.bak \
  -e "s/^  static const version = '.*';$/  static const version = '$VERSION';/" \
  -e "/^  static const sha256 =$/{n;s/'[0-9a-f]*';/'$SHA256';/;}" \
  "$CACHE_DART"
rm "$CACHE_DART.bak"

if ! grep -q "'$SHA256'" "$CACHE_DART"; then
  echo "Failed to update the checksum in $CACHE_DART" >&2
  exit 1
fi
echo "Updated bundletool $CURRENT -> $VERSION ($SHA256)" >&2
echo "$VERSION"
