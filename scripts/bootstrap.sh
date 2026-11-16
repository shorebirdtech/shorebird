#!/bin/bash
#
# Resolves every package in the repository, which is the whole workspace in the
# root pubspec.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# A Dart of the version CI runs, not whichever one PATH answers with. The
# reason is in tool/find_dart.sh.
source tool/find_dart.sh
find_dart "$(pwd)"
if [ -z "$dart_bin" ]; then
  exit 1
fi
export PATH="$(dirname "$dart_bin"):$PATH"

# One get for the workspace. This was `very_good packages get -r ./packages`
# from before the root pubspec listed a workspace, and very_good refuses
# without a Flutter SDK on PATH. Nothing here depends on Flutter.
dart pub get
