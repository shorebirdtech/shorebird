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
if ! command -v dart >/dev/null 2>&1; then
  echo 'error: dart not found, so nothing was verified' >&2
  exit 3
fi

# The checkout the caller stands in, not the one beside this script.
cd "$repo_root"
exec dart tool/agent_verify.dart "$@"
