#!/bin/bash
#
# Resolves every package in the repository, which is the whole workspace in the
# root pubspec.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# The standalone Dart, not whichever one PATH answers with. The reason, and
# why both directories are asked, is in tool/agent-verify.sh.
dart_bin="${DART_BIN:-}"
if [ -z "$dart_bin" ]; then
  while read -r candidate; do
    [ -x "$candidate" ] || continue
    [ -x "$(dirname "$candidate")/flutter" ] && continue
    resolved="$(realpath "$candidate" 2>/dev/null || echo "$candidate")"
    [ -x "$(dirname "$resolved")/flutter" ] && continue
    dart_bin="$candidate"
    break
  done < <(type -ap dart)
fi

if [ -z "$dart_bin" ]; then
  echo 'error: no standalone dart found, so nothing was fetched' >&2
  echo 'Install it: https://dart.dev/get-dart, or set DART_BIN to one' >&2
  exit 1
fi
export PATH="$(dirname "$dart_bin"):$PATH"

# One get for the workspace. This was `very_good packages get -r ./packages`
# from before the root pubspec listed a workspace, and very_good refuses
# without a Flutter SDK on PATH, which is what sent this script looking for
# `dart` beside a `flutter` in the first place. Nothing here depends on
# Flutter.
dart pub get
