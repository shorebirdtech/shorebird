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
    # Keep the default in sync with defaultFlutterGitUrl in shorebird_env.dart.
    git clone --filter=tree:0 "${SHOREBIRD_FLUTTER_GIT_URL:-https://github.com/shorebirdtech/flutter.git}" --no-checkout "$FLUTTER_PATH"
  fi
  # -c to avoid printing a warning about being in a detached head state.
  git -C "$FLUTTER_PATH" -c advice.detachedHead=false checkout "$FLUTTER_VERSION"
  SHOREBIRD_ENGINE_VERSION=`cat "$FLUTTER_PATH/bin/internal/engine.version"`
  echo "Shorebird Engine • revision $SHOREBIRD_ENGINE_VERSION"
  # Install Shorebird Flutter Artifacts. Keep the default and the trailing
  # slash handling in sync with ShorebirdEnv.downloadUrl.
  local download_url="${SHOREBIRD_DOWNLOAD_URL:-https://download.shorebird.dev}"
  FLUTTER_STORAGE_BASE_URL="${download_url%/}" $FLUTTER_PATH/bin/flutter --version
}

function pub_get_with_retry {
  local total_tries="10"
  local remaining_tries=$((total_tries - 1))
  # Install exactly the versions and bytes in the checked-in pubspec.lock, so
  # every install runs the dependencies we tested. The lockfile names pub.dev
  # as each package's source, so with a mirror (PUB_HOSTED_URL) pub can't use
  # it at all; resolve those installs as before.
  local enforce_lockfile=""
  case "${PUB_HOSTED_URL:-https://pub.dev}" in
    https://pub.dev|https://pub.dev/) enforce_lockfile="--enforce-lockfile" ;;
  esac
  while [[ "$remaining_tries" -gt 0 ]]; do
    (cd "$SHOREBIRD_CLI_DIR" && $DART_PATH pub get $enforce_lockfile) && break
    # 65: the pubspecs or a package's hash don't match pubspec.lock. Retrying
    # won't fix either.
    if [[ "$?" == 65 ]]; then
      >&2 echo "Error: Couldn't install the exact packages in Shorebird's pubspec.lock: a pubspec.yaml in $SHOREBIRD_ROOT changed, or a downloaded package's hash doesn't match the lockfile. Undo any local changes there (git -C \"$SHOREBIRD_ROOT\" status) and run shorebird again. If there are none, report it at https://github.com/shorebirdtech/shorebird/issues."
      return 1
    fi
    >&2 echo "Error: Unable to 'pub get' shorebird. Retrying in five seconds... ($remaining_tries tries left)"
    remaining_tries=$((remaining_tries - 1))
    sleep 5
  done

  if [[ "$remaining_tries" == 0 ]]; then
    >&2 echo "Command 'pub get' still failed after $total_tries tries, giving up."
    return 1
  fi
  return 0
}

# Prints this machine's platform as publish_cli.yaml names its binaries
# (macos-arm64, linux-x64, ...), or nothing when it builds none for it.
function prebuilt_platform {
  local os arch
  case "$(uname -s)" in
    Darwin) os=macos ;;
    Linux) os=linux ;;
    *) return 0 ;;
  esac
  local machine
  machine="$(uname -m)"
  # A shell under Rosetta reports x86_64 on Apple Silicon.
  if [[ "$os" == macos && "$machine" == x86_64 && "$(sysctl -n hw.optional.arm64 2>/dev/null)" == 1 ]]; then
    machine=arm64
  fi
  case "$machine" in
    x86_64|amd64) arch=x64 ;;
    arm64|aarch64) arch=arm64 ;;
    *) return 0 ;;
  esac
  echo "$os-$arch"
}

# Whether the CLI publish_cli.yaml built for this commit is installed.
function prebuilt_is_current {
  [[ -x "$PREBUILT_PATH" && -s "$PREBUILT_STAMP_PATH" && "$(cat "$PREBUILT_STAMP_PATH")" == "$REVISION" ]]
}

function sha256_of {
  if hash sha256sum 2>/dev/null; then
    sha256sum "$1" | cut -d' ' -f1
  elif hash shasum 2>/dev/null; then
    shasum -a 256 "$1" | cut -d' ' -f1
  else
    return 1
  fi
}

# Installs the CLI that publish_cli.yaml built for this commit (every commit
# pushed to stable has one): a ~5.5 MB download in place of cloning the pinned
# Flutter and compiling the CLI with its Dart SDK. Returns non-zero, leaving
# today's path to build it, when there is none to use: a commit with no
# binaries (main, a branch, a fork), local changes to what it's built from, a
# platform it isn't built for, no curl or unzip, a failed download, or a binary
# that doesn't start.
function install_prebuilt_cli {
  [[ -n "$REVISION" ]] || return 1
  local platform
  platform="$(prebuilt_platform)"
  [[ -n "$platform" ]] || return 1
  hash curl 2>/dev/null && hash unzip 2>/dev/null || return 1

  # The binary is the commit as published: with local changes, build those.
  local changes
  changes="$(git -C "$SHOREBIRD_ROOT" status --porcelain -- bin packages third_party pubspec.yaml pubspec.lock)" || return 1
  [[ -z "$changes" ]] || return 1

  # Keep the default and the trailing slash handling in sync with
  # ShorebirdEnv.downloadUrl.
  local download_url="${SHOREBIRD_DOWNLOAD_URL:-https://download.shorebird.dev}"
  local url="${download_url%/}/shorebird-cli/$REVISION/shorebird-$platform.zip"
  local tmp="$SHOREBIRD_ROOT/bin/cache/shorebird-cli.tmp"
  rm -rf "$tmp"
  mkdir -p "$tmp"

  # The checksum first, quietly: a commit with no binaries gets a 404 here,
  # and building it is the normal path for one, not an error.
  # Without a timeout, a network that drops packets would hold the startup
  # lock, and every other shorebird, for minutes before the fallback.
  local curl_args=(--fail --location --retry 3 --connect-timeout 10 --speed-limit 1024 --speed-time 30)
  if ! curl "${curl_args[@]}" --silent --output "$tmp/cli.zip.sha256" "$url.sha256"; then
    rm -rf "$tmp"
    return 1
  fi
  echo "Downloading Shorebird..."
  if ! curl "${curl_args[@]}" --silent --show-error --output "$tmp/cli.zip" "$url"; then
    echo "Couldn't download $url; building Shorebird instead."
    rm -rf "$tmp"
    return 1
  fi
  local expected actual
  expected="$(cut -d' ' -f1 < "$tmp/cli.zip.sha256")"
  actual="$(sha256_of "$tmp/cli.zip")" || actual=""
  if [[ -z "$expected" || "$actual" != "$expected" ]]; then
    echo "$url doesn't match its checksum; building Shorebird instead."
    rm -rf "$tmp"
    return 1
  fi
  if ! unzip -q -o "$tmp/cli.zip" -d "$tmp" || [[ ! -f "$tmp/shorebird" ]]; then
    echo "Couldn't unzip $url; building Shorebird instead."
    rm -rf "$tmp"
    return 1
  fi
  # Called as a condition, so set -e doesn't stop on these: check each.
  # A rename replaces the old binary even while it runs (shorebird upgrade).
  # The CLI finds its install from its own path, so it's checked in place.
  if ! chmod +x "$tmp/shorebird" || ! mv -f "$tmp/shorebird" "$PREBUILT_PATH"; then
    echo "Couldn't install the downloaded Shorebird; building it instead."
    rm -rf "$tmp"
    return 1
  fi
  rm -rf "$tmp"
  if ! "$PREBUILT_PATH" --version > /dev/null 2>&1; then
    echo "The downloaded Shorebird didn't start; building it instead."
    rm -f "$PREBUILT_PATH"
    return 1
  fi
  # One stamp at a time: what was set up last for HEAD is what runs.
  rm -f "$STAMP_PATH"
  echo "$REVISION" > "$PREBUILT_STAMP_PATH" || return 1
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

  if prebuilt_is_current; then
    exit 0
  fi

  local compilekey="$REVISION"

  # Invalidate cache if:
  #  * SNAPSHOT_PATH is not a file, or
  #  * STAMP_PATH is not a file, or
  #  * STAMP_PATH is an empty file, or
  #  * Contents of STAMP_PATH is not what we are going to compile, or
  #  * pubspec.yaml last modified after pubspec.lock
  if [[ ! -f "$SNAPSHOT_PATH" || ! -s "$STAMP_PATH" || "$(cat "$STAMP_PATH")" != "$compilekey" || "$SHOREBIRD_CLI_DIR/pubspec.yaml" -nt "$SHOREBIRD_ROOT/pubspec.lock" ]]; then
    # Waits for the update lock to be acquired. Placing this check inside the
    # conditional allows the majority of flutter/dart installations to bypass
    # the lock entirely, but as a result this required a second verification that
    # the SDK is up to date.
    _wait_for_lock

    # A different shell process might have updated the tool/SDK.
    if prebuilt_is_current; then
      exit 0
    fi
    if [[ -f "$SNAPSHOT_PATH" && -s "$STAMP_PATH" && "$(cat "$STAMP_PATH")" == "$compilekey" && "$SHOREBIRD_CLI_DIR/pubspec.yaml" -ot "$SHOREBIRD_ROOT/pubspec.lock" ]]; then
      exit $?
    fi

    if install_prebuilt_cli; then
      exit 0
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
    pub_get_with_retry
    # pub get may not update pubspec.lock's mtime if dependencies are unchanged,
    # which would cause the pubspec.yaml -nt pubspec.lock check above to keep
    # triggering a rebuild on every invocation.
    touch "$SHOREBIRD_ROOT/pubspec.lock"

    # Move the old snapshot - we can't just overwrite it as the VM might currently have it
    # memory mapped (e.g. on shorebird upgrade). For downloading a new dart sdk the folder is moved,
    # so we take the same approach of moving the file here.
    SNAPSHOT_PATH_OLD="$SNAPSHOT_PATH.old"
    if [ -f "$SNAPSHOT_PATH" ]; then
      mv "$SNAPSHOT_PATH" "$SNAPSHOT_PATH_OLD"
    fi

    # Compile...
    $DART_PATH --verbosity=error --disable-dart-dev --snapshot="$SNAPSHOT_PATH" --snapshot-kind="app-jit" --packages="$SHOREBIRD_ROOT/.dart_tool/package_config.json" --no-enable-mirrors "$SCRIPT_PATH" > /dev/null
    rm -f "$PREBUILT_STAMP_PATH"
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
  # The CLI publish_cli.yaml builds for each stable commit, and the commit it's
  # for. Its stamp is kept apart from the snapshot's, which bin/shorebird
  # clears whenever the pinned Flutter isn't installed (with this CLI it isn't).
  PREBUILT_PATH="$SHOREBIRD_ROOT/bin/cache/shorebird"
  PREBUILT_STAMP_PATH="$SHOREBIRD_ROOT/bin/cache/shorebird-cli.stamp"
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

  # Not fatal, as before: git refuses a checkout another user owns ("dubious
  # ownership", root in a container), and the snapshot path still runs.
  REVISION="$(cd "$SHOREBIRD_ROOT"; git rev-parse HEAD)" || REVISION=""

  # Setup output (git, flutter --version, pub get) goes to stderr, so stdout is
  # only the command's own: `$(shorebird flutter path)` and `--json` read it.
  upgrade_shorebird 7< "$PROG_NAME" 1>&2

  BIN_NAME="$(basename "$PROG_NAME")"
  case "$BIN_NAME" in    
    shorebird*)
      if prebuilt_is_current; then
        exec "$PREBUILT_PATH" "$@"
      fi
      exec "$DART_PATH" "$SNAPSHOT_PATH" "$@"
      ;;
    *)
      >&2 echo "Error! Executable name $BIN_NAME not recognized!"
      exit 1
      ;;
  esac
}
