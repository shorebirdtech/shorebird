#!/usr/bin/env bash
# Copyright 2014 The Flutter Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

set -e

# Needed because if it is set, cd may print the path it changed to.
unset CDPATH

# Either clones or pulls the Shorebird Flutter repository, depending on whether FLUTTER_PATH exists.
function update_flutter {
  if [[ -d "$FLUTTER_PATH" ]]; then
    git -C "$FLUTTER_PATH" fetch
  else
    git clone --filter=tree:0 https://github.com/shorebirdtech/flutter.git --no-checkout "$FLUTTER_PATH"
  fi
  # -c to avoid printing a warning about being in a detached head state.
  git -C "$FLUTTER_PATH" -c advice.detachedHead=false checkout "$FLUTTER_VERSION"
  SHOREBIRD_ENGINE_VERSION=`cat "$FLUTTER_PATH/bin/internal/engine.version"`
  echo "Shorebird Engine • revision $SHOREBIRD_ENGINE_VERSION"
  # Install Shorebird Flutter Artifacts
  FLUTTER_STORAGE_BASE_URL=https://download.shorebird.dev $FLUTTER_PATH/bin/flutter --version  
}

function pub_upgrade_with_retry {
  local total_tries="10"
  local remaining_tries=$((total_tries - 1))
  while [[ "$remaining_tries" -gt 0 ]]; do
    (cd "$SHOREBIRD_CLI_DIR" && $DART_PATH pub upgrade) && break
    >&2 echo "Error: Unable to 'pub upgrade' shorebird. Retrying in five seconds... ($remaining_tries tries left)"
    remaining_tries=$((remaining_tries - 1))
    sleep 5
  done

  if [[ "$remaining_tries" == 0 ]]; then
    >&2 echo "Command 'pub upgrade' still failed after $total_tries tries, giving up."
    return 1
  fi
  return 0
}

# Trap function for removing any remaining lock file at exit.
function _rmlock () {
  [ -n "$FLUTTER_UPGRADE_LOCK" ] && rm -rf "$FLUTTER_UPGRADE_LOCK"
}

# Determines which lock method to use, based on what is available on the system.
# Returns a non-zero value if the lock was not acquired, zero if acquired.
function _lock () {
  if hash flock 2>/dev/null; then
    flock --nonblock --exclusive 7 2>/dev/null
  elif hash shlock 2>/dev/null; then
    shlock -f "$1" -p $$
  else
    mkdir "$1" 2>/dev/null
  fi
}

# Waits for an update lock to be acquired.
#
# To ensure that we don't simultaneously update Dart in multiple parallel
# instances, we try to obtain an exclusive lock on this file descriptor (and
# thus this script's source file) while we are updating Dart and compiling the
# script. To do this, we try to use the command line program "flock", which is
# available on many Unix-like platforms, in particular on most Linux
# distributions. You give it a file descriptor, and it locks the corresponding
# file, having inherited the file descriptor from the shell.
#
# Complicating matters, there are two major scenarios where this will not
# work.
#
# The first is if the platform doesn't have "flock", for example on macOS. There
# is not a direct equivalent, so on platforms that don't have flock, we fall
# back to using trying to use the shlock command, and if that doesn't exist,
# then we use mkdir as an atomic operation to create a lock directory. If mkdir
# is able to create the directory, then the lock is acquired. To determine if we
# have "flock" or "shlock" available, we use the "hash" shell built-in.
#
# The second complication is on network file shares. On NFS, to obtain an
# exclusive lock you need a file descriptor that is open for writing. Thus, we
# ignore errors from flock by redirecting all output to /dev/null, since users
# will typically not care about errors from flock and are more likely to be
# confused by them than helped. The "shlock" method doesn't work for network
# shares, since it is PID-based. The "mkdir" method does work over NFS
# implementations that support atomic directory creation (which is most of
# them). The "schlock" and "flock" commands are more reliable than the mkdir
# method, however, or we would use mkdir in all cases.
#
# The upgrade_shorebird function calling _wait_for_lock is executed in a subshell
# with a redirect that pipes the source of this script into file descriptor 7.
# A flock lock is released when this subshell exits and file descriptor 7 is
# closed. The mkdir lock is released via an exit trap from the subshell that
# deletes the lock directory.
function _wait_for_lock () {
  FLUTTER_UPGRADE_LOCK="$SHOREBIRD_ROOT/bin/cache/.upgrade_lock"
  local waiting_message_displayed
  while ! _lock "$FLUTTER_UPGRADE_LOCK"; do
    if [[ -z $waiting_message_displayed ]]; then
      # Print with a return so that if the Dart code also prints this message
      # when it does its own lock, the message won't appear twice. Be sure that
      # the clearing printf below has the same number of space characters.
      printf "Waiting for another flutter command to release the startup lock...\r" >&2;
      waiting_message_displayed="true"
    fi
    sleep .1;
  done
  if [[ $waiting_message_displayed == "true" ]]; then
    # Clear the waiting message so it doesn't overlap any following text.
    printf "                                                                  \r" >&2;
  fi
  unset waiting_message_displayed
  # If the lock file is acquired, make sure that it is removed on exit.
  trap _rmlock INT TERM EXIT
}

# This function is always run in a subshell. Running the function in a subshell
# is required to make sure any lock directory is cleaned up by the exit trap in
# _wait_for_lock.
function upgrade_shorebird () (
  mkdir -p "$SHOREBIRD_ROOT/bin/cache"

  local revision="$(cd "$SHOREBIRD_ROOT"; git rev-parse HEAD)"
  local compilekey="$revision"

  # Invalidate cache if:
  #  * SNAPSHOT_PATH is not a file, or
  #  * STAMP_PATH is not a file, or
  #  * STAMP_PATH is an empty file, or
  #  * Contents of STAMP_PATH is not what we are going to compile, or
  #  * pubspec.yaml last modified after pubspec.lock
  if [[ ! -f "$SNAPSHOT_PATH" || ! -s "$STAMP_PATH" || "$(cat "$STAMP_PATH")" != "$compilekey" || "$SHOREBIRD_CLI_DIR/pubspec.yaml" -nt "$SHOREBIRD_CLI_DIR/pubspec.lock" ]]; then
    # Waits for the update lock to be acquired. Placing this check inside the
    # conditional allows the majority of flutter/dart installations to bypass
    # the lock entirely, but as a result this required a second verification that
    # the SDK is up to date.
    _wait_for_lock

    # A different shell process might have updated the tool/SDK.
    if [[ -f "$SNAPSHOT_PATH" && -s "$STAMP_PATH" && "$(cat "$STAMP_PATH")" == "$compilekey" && "$SHOREBIRD_CLI_DIR/pubspec.yaml" -ot "$SHOREBIRD_CLI_DIR/pubspec.lock" ]]; then
      exit $?
    fi

    >&2 echo Updating Flutter...
    update_flutter

    >&2 echo Building Shorebird...

    # Prepare packages...
    if [[ "$CI" == "true" || "$BOT" == "true" || "$CONTINUOUS_INTEGRATION" == "true" || "$CHROME_HEADLESS" == "1" ]]; then
      PUB_ENVIRONMENT="$PUB_ENVIRONMENT:shorebird_bot"
    else
      export PUB_SUMMARY_ONLY=1
    fi

    export PUB_ENVIRONMENT="$PUB_ENVIRONMENT:shorebird_install"
    pub_upgrade_with_retry

    # Move the old snapshot - we can't just overwrite it as the VM might currently have it
    # memory mapped (e.g. on shorebird upgrade). For downloading a new dart sdk the folder is moved,
    # so we take the same approach of moving the file here.
    SNAPSHOT_PATH_OLD="$SNAPSHOT_PATH.old"
    if [ -f "$SNAPSHOT_PATH" ]; then
      mv "$SNAPSHOT_PATH" "$SNAPSHOT_PATH_OLD"
    fi

    # Compile...
    $DART_PATH --verbosity=error --disable-dart-dev --snapshot="$SNAPSHOT_PATH" --snapshot-kind="app-jit" --packages="$SHOREBIRD_CLI_DIR/.dart_tool/package_config.json" --no-enable-mirrors "$SCRIPT_PATH" > /dev/null
    echo "$compilekey" > "$STAMP_PATH"

    # Delete any temporary snapshot path.
    if [ -f "$SNAPSHOT_PATH_OLD" ]; then
      rm -f "$SNAPSHOT_PATH_OLD"
    fi
  fi
  # The exit here is extraneous since the function is run in a subshell, but
  # this serves as documentation that running the function in a subshell is
  # required to make sure any lock directory created by mkdir is cleaned up.
  exit $?
)

# This function is intended to be executed by entrypoints (e.g. `//bin/shorebird`). 
# PROG_NAME and BIN_DIR should already be set by those entrypoints.
function shared::execute() {
  export SHOREBIRD_ROOT="$(cd "${BIN_DIR}/.." ; pwd -P)"

  SHOREBIRD_CLI_DIR="$SHOREBIRD_ROOT/packages/shorebird_cli"
  SNAPSHOT_PATH="$SHOREBIRD_ROOT/bin/cache/shorebird.snapshot"
  STAMP_PATH="$SHOREBIRD_ROOT/bin/cache/shorebird.stamp"
  SCRIPT_PATH="$SHOREBIRD_CLI_DIR/bin/shorebird.dart"
  FLUTTER_PATH="$SHOREBIRD_ROOT/bin/cache/flutter/$FLUTTER_VERSION"
  export DART_PATH="$FLUTTER_PATH/bin/cache/dart-sdk/bin/dart"

  # Test if running as superuser – but don't warn if running within Docker or CI.
  if [[ "$EUID" == "0" && ! -f /.dockerenv && "$CI" != "true" && "$BOT" != "true" && "$CONTINUOUS_INTEGRATION" != "true" ]]; then
    >&2 echo "   Woah! You appear to be trying to run shorebird as root."
    >&2 echo "   We strongly recommend running shorebird without superuser privileges."
    >&2 echo "  /"
    >&2 echo "📎"
  fi

  # Test if Git is available on the Host
  if ! hash git 2>/dev/null; then
    >&2 echo "Error: Unable to find git in your PATH."
    exit 1
  fi

  # Test if the shorebird directory is a git clone (otherwise git rev-parse HEAD
  # would fail)
  if [[ ! -e "$SHOREBIRD_ROOT/.git" ]]; then
    >&2 echo "Error: The shorebird directory is not a clone of the GitHub project."
    >&2 echo "       The shorebird tools requires Git in order to operate properly;"
    >&2 echo "       to install Shorebird, see the instructions at:"
    >&2 echo "       https://github.com/shorebirdtech/shorebird"
    exit 1
  fi

  upgrade_shorebird 7< "$PROG_NAME"

  BIN_NAME="$(basename "$PROG_NAME")"
  case "$BIN_NAME" in    
    shorebird*)
      exec "$DART_PATH" "$SNAPSHOT_PATH" "$@"
      ;;
    *)
      >&2 echo "Error! Executable name $BIN_NAME not recognized!"
      exit 1
      ;;
  esac
}