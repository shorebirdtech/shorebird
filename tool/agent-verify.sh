#!/usr/bin/env bash
#
# Runs dart format, analyze and test over every workspace package, as CI
# does, skipping each package whose inputs already passed in any worktree.
# The work is in tool/agent_verify.dart; the cache is packages/verify_cache.
#
# Usage: tool/agent-verify.sh [--plan] [--force]
#
#   --plan   Print the packages it would check and exit.
#   --force  Check every package, even those that already passed.
#
# Exit codes: 0 every package passed, 1 a check failed, 2 usage error,
# 3 the workspace could not be resolved, so nothing was checked.
set -euo pipefail

# An inherited GIT_DIR or GIT_WORK_TREE (a hook, `git rebase --exec`) makes
# --show-toplevel name the working directory rather than the root.
if ! repo_root="$(env -u GIT_DIR -u GIT_WORK_TREE git rev-parse --show-toplevel)"; then
  echo "error: $(pwd) is not in a git checkout, so there is nothing to verify" >&2
  exit 2
fi
if [ ! -f "$repo_root/tool/agent_verify.dart" ]; then
  echo "error: $repo_root has no tool/agent_verify.dart, so it is not a checkout of shorebirdtech/shorebird or is one from before agent-verify" >&2
  exit 2
fi

# The standalone Dart SDK, which is the one CI installs with
# dart-lang/setup-dart and the only one this repository wants: nothing here
# depends on Flutter. A machine that also has a Flutter checkout has that
# checkout's Dart too, several releases behind, and PATH's answer between the
# two depends on who is asking, so a terminal resolves CI's Dart and a script
# resolves Flutter's. The two disagree about `dart format`, which is a verify
# that passes here and fails CI's format step, and `--tool dart` puts the
# version in every package's cache key, so the two also take turns rechecking
# work the other already passed. Skipping any `dart` beside a `flutter` is the
# whole rule, and the chosen one goes in front of PATH so agent_verify.dart,
# the checks it starts and the key itself all name it rather than resolving
# again.
dart_bin=""
while read -r candidate; do
  [ -x "$candidate" ] || continue
  # Through the symlink: a `dart` a package manager installed sits in a bin
  # directory holding every other formula's stubs, so only the real file's
  # neighbours say which SDK it belongs to.
  resolved="$(realpath "$candidate" 2>/dev/null || echo "$candidate")"
  [ -x "${resolved%/dart}/flutter" ] && continue
  dart_bin="$candidate"
  break
done < <(type -ap dart)

# Without one nothing ran, which is not a pass.
if [ -z "$dart_bin" ]; then
  echo 'error: no standalone dart found, so nothing was verified' >&2
  echo 'Install it: https://dart.dev/get-dart' >&2
  exit 3
fi
export PATH="${dart_bin%/dart}:$PATH"
# To stderr, because --plan's stdout is a list meant to be read by something
# else.
echo "agent-verify: $dart_bin, $(dart --version 2>&1)" >&2

# The checkout the caller stands in, not the one beside this script.
cd "$repo_root"
exec dart tool/agent_verify.dart "$@"
