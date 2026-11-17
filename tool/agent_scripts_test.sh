#!/usr/bin/env bash
# cspell:words dartsdk nongit stubbin sysbin
#
# Tests tool/find_dart.sh and tool/agent-verify.sh with no network and no real
# Dart SDK, using stub curl and dart binaries.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT

sysbin="$tmp_root/sysbin"
mkdir -p "$sysbin"
for cmd in git zip unzip sed mkdir dirname cat realpath uname find mktemp cut mv rmdir rm sleep env bash sh tr ls wc touch chmod cp; do
  if p="$(command -v "$cmd" 2>/dev/null)"; then
    ln -sf "$p" "$sysbin/$cmd"
  else
    echo "error: required command '$cmd' not found on PATH" >&2
    exit 1
  fi
done
for cmd in shasum sha256sum; do
  if p="$(command -v "$cmd" 2>/dev/null)"; then
    ln -sf "$p" "$sysbin/$cmd"
  fi
done

if command -v shasum >/dev/null 2>&1; then
  sha256_file() { shasum -a 256 "$1" | cut -d' ' -f1; }
else
  sha256_file() { sha256sum "$1" | cut -d' ' -f1; }
fi

case "$(uname -s)" in
  Darwin) host_os=macos ;;
  Linux) host_os=linux ;;
  *) echo "error: unsupported OS $(uname -s)" >&2; exit 1 ;;
esac
case "$(uname -m)" in
  arm64 | aarch64) host_arch=arm64 ;;
  x86_64 | amd64) host_arch=x64 ;;
  *) echo "error: unsupported arch $(uname -m)" >&2; exit 1 ;;
esac

fake_version="99.99.99"

# Build a minimal zip containing dart-sdk/bin/dart that reports $fake_version.
sdk_stage="$tmp_root/sdk_stage"
mkdir -p "$sdk_stage/dart-sdk/bin"
cat >"$sdk_stage/dart-sdk/bin/dart" <<EOF
#!/usr/bin/env sh
if [ "\${1:-}" = "--version" ]; then
  echo 'Dart SDK version: $fake_version (stable) (stub) on "stub"'
  exit 0
fi
exit 0
EOF
chmod +x "$sdk_stage/dart-sdk/bin/dart"
(cd "$sdk_stage" && zip -q -r "$tmp_root/sdk.zip" dart-sdk)
sdk_sha="$(sha256_file "$tmp_root/sdk.zip")"
printf '%s  dartsdk-stub-release.zip\n' "$sdk_sha" >"$tmp_root/sdk.zip.sha256sum"

# Initialize a clean repo fixture with copies of tool/ scripts so tests never
# touch the caller's .dart_tool/ci_dart_version or worktree state.
make_repo_fixture() {
  local dir="$1"
  mkdir -p "$dir/tool"
  git init -q "$dir"
  cp "$repo_root/tool/find_dart.sh" "$dir/tool/find_dart.sh"
  cp "$repo_root/tool/agent-verify.sh" "$dir/tool/agent-verify.sh"
  chmod +x "$dir/tool/agent-verify.sh"
  touch "$dir/tool/agent_verify.dart"
}

# Write a stub curl into $1 that serves VERSION, sdk.zip, and sdk.zip.sha256sum
# from $tmp_root. Optional $2 is a barrier directory for the two-fetch race.
write_stub_curl() {
  local bin_dir="$1" race_dir="${2:-}"
  mkdir -p "$bin_dir"
  cat >"$bin_dir/curl" <<EOF
#!/usr/bin/env bash
set -euo pipefail
out=""
url=""
while [ \$# -gt 0 ]; do
  case "\$1" in
    -o) out="\$2"; shift 2 ;;
    --max-time) shift 2 ;;
    -*) shift ;;
    *) url="\$1"; shift ;;
  esac
done
case "\$url" in
  */VERSION)
    printf '{"version": "%s"}\n' "$fake_version"
    ;;
  *.zip)
    if [ -n "$race_dir" ]; then
      mkdir -p "$race_dir"
      : >"$race_dir/\$\$"
      # Backdate the lock while holding it across the download so a waiting
      # fetch exercises its stale-lock check against a live holder.
      touch -t 202001010000 "\$(dirname "\$(dirname "\$out")")"/.install.* 2>/dev/null || true
      sleep 1.5
    fi
    cp "$tmp_root/sdk.zip" "\$out"
    ;;
  *.zip.sha256sum)
    cp "$tmp_root/sdk.zip.sha256sum" "\$out"
    ;;
  *)
    echo "stub curl: unexpected URL \$url" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "$bin_dir/curl"
}

assert_eq() {
  local got="$1" want="$2" msg="$3"
  if [ "$got" != "$want" ]; then
    echo "FAIL: $msg (got '$got', want '$want')" >&2
    exit 1
  fi
}

assert_no_leftovers() {
  local root="$1" msg="$2"
  local leftover
  leftover="$(find "$root" -maxdepth 1 \( -name '.fetch.*' -o -name '.install.*' \))"
  if [ -n "$leftover" ]; then
    echo "FAIL: $msg: leftover temp/lock entries: $leftover" >&2
    exit 1
  fi
}

run_case() {
  local name="$1"
  shift
  ("$@")
  echo "PASS: $name"
}

# 1. SDK fetch against stub curl
test_sdk_fetch() {
  local case_dir="$tmp_root/case_fetch"
  local repo="$case_dir/repo" stub_bin="$case_dir/stubbin"
  make_repo_fixture "$repo"
  write_stub_curl "$stub_bin"
  export PATH="$stub_bin:$sysbin"
  export XDG_CACHE_HOME="$case_dir/cache"
  export HOME="$case_dir/home"
  unset DART_BIN

  # shellcheck source=/dev/null
  source "$repo/tool/find_dart.sh"
  dart_bin=""
  find_dart "$repo"

  local want_dest="$XDG_CACHE_HOME/shorebird-dart-sdks/dartsdk-$host_os-$host_arch-$fake_version"
  assert_eq "$dart_bin" "$want_dest/dart-sdk/bin/dart" "sdk fetch dart_bin path"
  assert_eq "$(_find_dart_version_of "$dart_bin")" "$fake_version" "sdk fetch dart version"
  assert_eq "$(cat "$repo/.dart_tool/ci_dart_version")" "$fake_version" "cached ci_dart_version"
  assert_no_leftovers "$XDG_CACHE_HOME/shorebird-dart-sdks" "sdk fetch"
}

# 2. Cache recovery when dest exists without a working SDK
test_cache_recovery() {
  local case_dir="$tmp_root/case_recovery"
  local repo="$case_dir/repo" stub_bin="$case_dir/stubbin"
  make_repo_fixture "$repo"
  write_stub_curl "$stub_bin"
  export PATH="$stub_bin:$sysbin"
  export XDG_CACHE_HOME="$case_dir/cache"
  export HOME="$case_dir/home"
  unset DART_BIN

  local dest="$XDG_CACHE_HOME/shorebird-dart-sdks/dartsdk-$host_os-$host_arch-$fake_version"
  mkdir -p "$dest/dart-sdk/bin"
  printf '#!/bin/sh\nexit 1\n' >"$dest/dart-sdk/bin/dart"
  chmod +x "$dest/dart-sdk/bin/dart"
  touch "$dest/stale-marker"

  (cd "$repo" && "$repo/tool/agent-verify.sh" >/dev/null 2>&1)
  if [ -e "$dest/stale-marker" ]; then
    echo "FAIL: stale-marker survived cache recovery" >&2
    exit 1
  fi
  # shellcheck source=/dev/null
  source "$repo/tool/find_dart.sh"
  assert_eq "$(_find_dart_version_of "$dest/dart-sdk/bin/dart")" "$fake_version" "recovered sdk version"
  assert_no_leftovers "$XDG_CACHE_HOME/shorebird-dart-sdks" "cache recovery"
}

# 3. Two-fetch race: winner downloads and installs, loser waits under lock and
# rechecks cache without downloading or reaping the live lock
test_two_fetch_race() {
  local case_dir="$tmp_root/case_race"
  local repo="$case_dir/repo" stub_bin="$case_dir/stubbin" race_dir="$case_dir/race"
  make_repo_fixture "$repo"
  write_stub_curl "$stub_bin" "$race_dir"
  export PATH="$stub_bin:$sysbin"
  export XDG_CACHE_HOME="$case_dir/cache"
  export HOME="$case_dir/home"
  unset DART_BIN

  (cd "$repo" && "$repo/tool/agent-verify.sh" >/dev/null 2>"$case_dir/err1") &
  local pid1=$!
  (cd "$repo" && "$repo/tool/agent-verify.sh" >/dev/null 2>"$case_dir/err2") &
  local pid2=$!
  wait "$pid1"
  wait "$pid2"

  local want_bin="$XDG_CACHE_HOME/shorebird-dart-sdks/dartsdk-$host_os-$host_arch-$fake_version/dart-sdk/bin/dart"
  assert_eq "$(find "$race_dir" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" "1" "only one fetch downloaded the sdk"
  # shellcheck source=/dev/null
  source "$repo/tool/find_dart.sh"
  assert_eq "$(_find_dart_version_of "$want_bin")" "$fake_version" "race cached sdk version"
  assert_no_leftovers "$XDG_CACHE_HOME/shorebird-dart-sdks" "two-fetch race"
}

# 3b. Dead lock holder is reaped rather than waited out
test_dead_lock_reap() {
  local case_dir="$tmp_root/case_dead_lock"
  local repo="$case_dir/repo" stub_bin="$case_dir/stubbin"
  make_repo_fixture "$repo"
  write_stub_curl "$stub_bin"
  export PATH="$stub_bin:$sysbin"
  export XDG_CACHE_HOME="$case_dir/cache"
  export HOME="$case_dir/home"
  unset DART_BIN

  local lock="$XDG_CACHE_HOME/shorebird-dart-sdks/.install.$host_os-$host_arch-$fake_version"
  mkdir -p "$lock"
  # Spawn and reap a short-lived process to get a guaranteed-dead PID.
  sh -c 'exit 0' &
  local dead_pid=$!
  wait "$dead_pid"
  printf '%s\n' "$dead_pid" >"$lock/pid"

  # shellcheck source=/dev/null
  source "$repo/tool/find_dart.sh"
  dart_bin=""
  find_dart "$repo" 2>/dev/null

  local want_bin="$XDG_CACHE_HOME/shorebird-dart-sdks/dartsdk-$host_os-$host_arch-$fake_version/dart-sdk/bin/dart"
  assert_eq "$dart_bin" "$want_bin" "dead lock reaped and sdk fetched"
  assert_no_leftovers "$XDG_CACHE_HOME/shorebird-dart-sdks" "dead lock reap"
}

write_stub_dart() {
  local bin_dir="$1" verify_exit="$2" args_log="${3:-}"
  mkdir -p "$bin_dir"
  cat >"$bin_dir/dart" <<EOF
#!/usr/bin/env sh
if [ "\${1:-}" = "--version" ]; then
  echo 'Dart SDK version: $fake_version (stable) (stub) on "stub"'
  exit 0
fi
if [ -n "$args_log" ]; then
  printf '%s\n' "\$*" >"$args_log"
fi
exit $verify_exit
EOF
  chmod +x "$bin_dir/dart"
}

# 4. agent-verify.sh exit 0 against stub dart
test_verify_exit_0() {
  local case_dir="$tmp_root/case_exit0"
  local repo="$case_dir/repo" stub_bin="$case_dir/stubbin"
  make_repo_fixture "$repo"
  write_stub_curl "$stub_bin"
  write_stub_dart "$stub_bin" 0 "$case_dir/args.log"
  export PATH="$stub_bin:$sysbin"
  export XDG_CACHE_HOME="$case_dir/cache"
  export HOME="$case_dir/home"
  unset DART_BIN

  local rc=0
  (cd "$repo" && "$repo/tool/agent-verify.sh" --plan >/dev/null 2>&1) || rc=$?
  assert_eq "$rc" "0" "agent-verify.sh exit 0"
  assert_eq "$(cat "$case_dir/args.log")" "tool/agent_verify.dart --plan" "stub dart args"
}

# 5. agent-verify.sh exit 1 against stub dart
test_verify_exit_1() {
  local case_dir="$tmp_root/case_exit1"
  local repo="$case_dir/repo" stub_bin="$case_dir/stubbin"
  make_repo_fixture "$repo"
  write_stub_curl "$stub_bin"
  write_stub_dart "$stub_bin" 1
  export PATH="$stub_bin:$sysbin"
  export XDG_CACHE_HOME="$case_dir/cache"
  export HOME="$case_dir/home"
  unset DART_BIN

  local rc=0
  (cd "$repo" && "$repo/tool/agent-verify.sh" >/dev/null 2>&1) || rc=$?
  assert_eq "$rc" "1" "agent-verify.sh exit 1"
}

# 6. agent-verify.sh exit 2 (usage / missing repo or agent_verify.dart)
test_verify_exit_2() {
  local case_dir="$tmp_root/case_exit2"
  local repo="$case_dir/repo" nongit="$case_dir/nongit" empty_repo="$case_dir/empty_repo"
  make_repo_fixture "$repo"
  mkdir -p "$nongit" "$empty_repo"
  git init -q "$empty_repo"
  export PATH="$sysbin"
  export XDG_CACHE_HOME="$case_dir/cache"
  export HOME="$case_dir/home"
  unset DART_BIN

  local rc=0
  (cd "$nongit" && "$repo/tool/agent-verify.sh" >/dev/null 2>&1) || rc=$?
  assert_eq "$rc" "2" "agent-verify.sh exit 2 outside git"

  rc=0
  (cd "$empty_repo" && "$repo/tool/agent-verify.sh" >/dev/null 2>&1) || rc=$?
  assert_eq "$rc" "2" "agent-verify.sh exit 2 without tool/agent_verify.dart"
}

# 7. agent-verify.sh exit 3 (no Dart / offline without cached version)
test_verify_exit_3() {
  local case_dir="$tmp_root/case_exit3"
  local repo="$case_dir/repo" stub_bin="$case_dir/stubbin"
  make_repo_fixture "$repo"
  mkdir -p "$stub_bin"
  cat >"$stub_bin/curl" <<'EOF'
#!/usr/bin/env sh
exit 1
EOF
  chmod +x "$stub_bin/curl"
  export PATH="$stub_bin:$sysbin"
  export XDG_CACHE_HOME="$case_dir/cache"
  export HOME="$case_dir/home"
  unset DART_BIN

  local rc=0
  (cd "$repo" && "$repo/tool/agent-verify.sh" >/dev/null 2>&1) || rc=$?
  assert_eq "$rc" "3" "agent-verify.sh exit 3 when no Dart resolves"
}

run_case "sdk_fetch" test_sdk_fetch
run_case "cache_recovery" test_cache_recovery
run_case "two_fetch_race" test_two_fetch_race
run_case "dead_lock_reap" test_dead_lock_reap
run_case "verify_exit_0" test_verify_exit_0
run_case "verify_exit_1" test_verify_exit_1
run_case "verify_exit_2" test_verify_exit_2
run_case "verify_exit_3" test_verify_exit_3
