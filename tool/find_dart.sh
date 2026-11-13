# cspell:words dartsdk
# Sourced by tool/agent-verify.sh and scripts/bootstrap.sh. Sets dart_bin to
# a Dart SDK binary of the version CI runs, or leaves it empty and prints why
# to stderr.
#
# CI installs Dart with dart-lang/setup-dart and no `sdk:`, which is the
# current stable. What `dart format` does is set by the Dart version, the
# package's language version and analysis_options.yaml, so any Dart of CI's
# version gives CI's verdict, wherever it lives: a standalone install, or the
# one inside a Flutter checkout. A different version can format differently,
# and its verdict is worse than none, so it is refused.
#
# When no Dart on PATH is that version, CI's SDK is fetched from the archive
# setup-dart installs it from, into a cache outside every checkout, so a
# machine whose package manager is behind stable still verifies as CI does and
# every worktree shares the one copy.
#
# CI's version is the one setup-dart resolves "stable" to, read from the same
# place. The last answer is kept in .dart_tool so an offline run still knows
# it. DART_BIN skips the check: naming a Dart is choosing it.

_find_dart_ci_version() {
  local cache="$1/.dart_tool/ci_dart_version" fetched
  fetched="$(curl -fsS --max-time 5 \
    https://storage.googleapis.com/dart-archive/channels/stable/release/latest/VERSION \
    2>/dev/null | sed -n 's/.*"version": *"\([^"]*\)".*/\1/p')" || true
  if [ -n "$fetched" ]; then
    mkdir -p "$(dirname "$cache")"
    echo "$fetched" >"$cache"
    echo "$fetched"
  elif [ -f "$cache" ]; then
    echo "find_dart: offline, using CI's Dart version from the last check ($cache)" >&2
    cat "$cache"
  fi
}

# A Flutter checkout's bin/dart is a wrapper that may update or lock the
# checkout before it runs. The SDK it wraps, in bin/cache/dart-sdk, is the
# same Dart without that.
_find_dart_sdk_binary() {
  local resolved dir
  resolved="$(realpath "$1" 2>/dev/null || echo "$1")"
  dir="$(dirname "$resolved")"
  if [ -x "$dir/cache/dart-sdk/bin/dart" ]; then
    echo "$dir/cache/dart-sdk/bin/dart"
  else
    # Not the resolved file: a mise shim resolves to the mise binary, which
    # only acts as dart when called by the shim's name.
    echo "$1"
  fi
}

# Empty when it isn't a working dart (an asdf shim with no version set, a
# Flutter checkout whose cache isn't filled): skip it, don't fail the caller.
_find_dart_version_of() {
  { "$1" --version 2>&1 || true; } | sed -n 's/^Dart SDK version: \([^ ]*\).*/\1/p'
}

# Echoes a Dart of version $1, fetching it from the archive unless a past run
# already did. Empty, with the reason on stderr, when it could not be had.
_find_dart_fetched() {
  local want="$1" root dest url tmp published computed os arch sum
  case "$(uname -s)" in
    Darwin) os=macos ;;
    Linux) os=linux ;;
    *) echo "find_dart: Dart $want was not fetched, no archive build is chosen for $(uname -s)" >&2; return 0 ;;
  esac
  case "$(uname -m)" in
    arm64 | aarch64) arch=arm64 ;;
    x86_64 | amd64) arch=x64 ;;
    *) echo "find_dart: Dart $want was not fetched, no archive build is chosen for $(uname -m)" >&2; return 0 ;;
  esac
  # Where verify_cache keeps its own cache: outside every checkout, so every
  # worktree reads the one SDK, and under XDG_CACHE_HOME when it is set. A
  # caller with neither that nor HOME is told so, rather than aborted by
  # set -u or handed a cache at the filesystem root.
  if [ -z "${XDG_CACHE_HOME:-${HOME:-}}" ]; then
    echo "find_dart: Dart $want was not fetched, neither XDG_CACHE_HOME nor HOME says where to keep it" >&2
    return 0
  fi
  root="${XDG_CACHE_HOME:-$HOME/.cache}/shorebird-dart-sdks"
  dest="$root/dartsdk-$os-$arch-$want"
  if [ "$(_find_dart_version_of "$dest/dart-sdk/bin/dart")" = "$want" ]; then
    echo "$dest/dart-sdk/bin/dart"
    return 0
  fi

  if ! command -v curl >/dev/null || ! command -v unzip >/dev/null; then
    echo "find_dart: fetching Dart $want needs curl and unzip" >&2
    return 0
  fi
  # No tool to check what was downloaded means no fetch: an SDK nothing
  # checked is worse than an error a person can act on.
  if command -v shasum >/dev/null; then
    sum="shasum -a 256"
  elif command -v sha256sum >/dev/null; then
    sum="sha256sum"
  else
    echo "find_dart: fetching Dart $want needs shasum or sha256sum to check what it downloaded" >&2
    return 0
  fi

  url="https://storage.googleapis.com/dart-archive/channels/stable/release/$want/sdk/dartsdk-$os-$arch-release.zip"
  mkdir -p "$root" || return 0
  # A fetch killed partway leaves its zip behind, and no fetch runs for a day.
  find "$root" -maxdepth 1 -name '.fetch.*' -mtime +1 -exec rm -rf {} + 2>/dev/null || true
  tmp="$(mktemp -d "$root/.fetch.XXXXXX")" || return 0
  echo "find_dart: fetching Dart $want, the stable Dart CI runs, into $dest" >&2
  # The SDK is a few hundred megabytes, so a person watching gets curl's
  # progress bar rather than minutes of silence.
  local progress=(-s)
  [ -t 2 ] && progress=(--progress-bar)
  if ! curl -fSL "${progress[@]}" --max-time 1800 -o "$tmp/sdk.zip" "$url" ||
    ! curl -fsSL --max-time 30 -o "$tmp/sdk.zip.sha256sum" "$url.sha256sum"; then
    echo "find_dart: could not download $url" >&2
    rm -rf "$tmp"
    return 0
  fi
  published="$(cut -d' ' -f1 <"$tmp/sdk.zip.sha256sum")"
  computed="$($sum "$tmp/sdk.zip" | cut -d' ' -f1)"
  if [ -z "$published" ] || [ "$computed" != "$published" ]; then
    echo "find_dart: $url does not match the sha256 published beside it, so it was discarded" >&2
    rm -rf "$tmp"
    return 0
  fi
  if ! unzip -q "$tmp/sdk.zip" -d "$tmp/unpacked"; then
    echo "find_dart: could not unpack the Dart $want SDK" >&2
    rm -rf "$tmp"
    return 0
  fi

  # A rename, so no other worktree reads a half-unpacked SDK. Two fetching at
  # once each unpack a whole one and the second lands inside the first's
  # directory rather than over it, so it is the copy that gets thrown away.
  mv "$tmp/unpacked" "$dest" 2>/dev/null || true
  rm -rf "$tmp" "$dest/unpacked"
  if [ "$(_find_dart_version_of "$dest/dart-sdk/bin/dart")" = "$want" ]; then
    echo "$dest/dart-sdk/bin/dart"
    return 0
  fi
  echo "find_dart: the SDK $url served is not Dart $want" >&2
}

find_dart() {
  local repo_root="$1" want candidate sdk_bin have tried=""
  dart_bin="${DART_BIN:-}"
  [ -n "$dart_bin" ] && return 0

  want="$(_find_dart_ci_version "$repo_root")"
  if [ -z "$want" ]; then
    echo "error: could not read CI's Dart version (stable, from storage.googleapis.com/dart-archive) and none is cached, so no Dart was chosen" >&2
    echo "Connect once, or set DART_BIN to the Dart to use" >&2
    return 0
  fi

  while read -r candidate; do
    [ -x "$candidate" ] || continue
    sdk_bin="$(_find_dart_sdk_binary "$candidate")"
    [ -x "$sdk_bin" ] || continue
    have="$(_find_dart_version_of "$sdk_bin")" || have=""
    if [ "$have" = "$want" ]; then
      dart_bin="$sdk_bin"
      return 0
    fi
    tried="$tried  $candidate: ${have:-unknown version}"$'\n'
  done < <(type -ap dart)

  dart_bin="$(_find_dart_fetched "$want")"
  [ -n "$dart_bin" ] && return 0

  echo "error: no dart on PATH is $want, the stable Dart CI runs, and fetching it failed" >&2
  [ -n "$tried" ] && printf 'Found:\n%s' "$tried" >&2
  echo "Install Dart $want (https://dart.dev/get-dart), run \`flutter --version\` in the Flutter checkout whose dart is on PATH to update it, or set DART_BIN" >&2
}
