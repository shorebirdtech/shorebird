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
    echo "$resolved"
  fi
}

_find_dart_version_of() {
  "$1" --version 2>&1 | sed -n 's/^Dart SDK version: \([^ ]*\).*/\1/p'
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
    have="$(_find_dart_version_of "$sdk_bin")"
    if [ "$have" = "$want" ]; then
      dart_bin="$sdk_bin"
      return 0
    fi
    tried="$tried  $candidate: ${have:-unknown version}"$'\n'
  done < <(type -ap dart)

  echo "error: no dart on PATH is $want, the stable Dart CI runs" >&2
  [ -n "$tried" ] && printf 'Found:\n%s' "$tried" >&2
  echo "Install Dart $want (https://dart.dev/get-dart), update the Flutter checkout whose dart is on PATH, or set DART_BIN" >&2
}
