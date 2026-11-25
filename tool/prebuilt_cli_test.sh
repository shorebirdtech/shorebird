#!/usr/bin/env bash
#
# Tests install_prebuilt_cli (third_party/flutter/bin/internal/shared.sh), how
# bin/shorebird installs the CLI publish_cli.yaml built for a stable commit:
# against a throwaway SHOREBIRD_ROOT and a local HTTP server holding a fake
# CLI, a shell script that prints a version. publish_cli.yaml checks the real
# binary; this checks the install around it: that it installs, and that
# every way it can't leaves nothing behind for bin/shorebird to build over.
#
# Needs bash, git, curl, unzip and python3 (the server and the zips).
# Usage: tool/prebuilt_cli_test.sh
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_root="$(mktemp -d)"
server_pid=""
cleanup() {
  if [[ -n "$server_pid" ]]; then
    kill "$server_pid" 2>/dev/null
    wait "$server_pid" 2>/dev/null
  fi
  rm -rf "$tmp_root"
}
trap cleanup EXIT

# The functions under test. shared.sh turns on set -e, which the real callers
# also run under: install_prebuilt_cli is always called as a condition there,
# as here.
# shellcheck disable=SC1091
source "$repo_root/third_party/flutter/bin/internal/shared.sh"
set +e

platform="$(prebuilt_platform)"
if [[ -z "$platform" ]]; then
  echo "error: no prebuilt CLI is published for $(uname -sm)" >&2
  exit 1
fi

sha256_file() { sha256_of "$1"; }

# The server's root. Each case publishes there for its own REVISION.
www="$tmp_root/www"
mkdir -p "$www"
python3 -u -m http.server 0 --bind 127.0.0.1 --directory "$www" \
  > "$tmp_root/server.log" 2>&1 &
server_pid=$!
for _ in $(seq 50); do
  port="$(sed -n 's/.* port \([0-9]*\).*/\1/p' "$tmp_root/server.log" | head -1)"
  [[ -n "$port" ]] && break
  sleep 0.1
done
if [[ -z "${port:-}" ]]; then
  echo "error: the HTTP server didn't start:" >&2
  cat "$tmp_root/server.log" >&2
  exit 1
fi
export SHOREBIRD_DOWNLOAD_URL="http://127.0.0.1:$port/"

# A fake CLI: a script printing [version], exiting [code] for --version.
fake_cli() {
  local dir="$1" version="$2" code="${3:-0}"
  mkdir -p "$dir"
  printf '#!/bin/sh\necho "Shorebird %s"\nexit %s\n' "$version" "$code" > "$dir/shorebird"
  chmod +x "$dir/shorebird"
}

# Publishes [zip] for REVISION as publish_cli.yaml does: the zip and its
# checksum ([sha], default the zip's own).
publish() {
  local zip="$1" sha="${2:-}"
  local dir="$www/shorebird-cli/$REVISION"
  mkdir -p "$dir"
  cp "$zip" "$dir/shorebird-$platform.zip"
  [[ -n "$sha" ]] || sha="$(sha256_file "$zip")"
  echo "$sha  shorebird-$platform.zip" > "$dir/shorebird-$platform.zip.sha256"
}

# Zips a fake CLI printing [version] (exit [code]) and publishes it.
publish_cli() {
  local version="$1" code="${2:-0}"
  local src
  src="$(mktemp -d "$tmp_root/src.XXXXXX")"
  fake_cli "$src" "$version" "$code"
  (cd "$src" && python3 -m zipfile -c "$src.zip" shorebird)
  publish "$src.zip"
}

# A fresh SHOREBIRD_ROOT: a git repo with one commit holding what the
# install checks for local changes, and nothing published yet. Sets the paths
# shared::execute sets. Two roots made in the same second have the same
# REVISION, so each case empties the server.
new_root() {
  rm -rf "${www:?}"/*
  SHOREBIRD_ROOT="$(mktemp -d "$tmp_root/root.XXXXXX")"
  mkdir -p "$SHOREBIRD_ROOT/bin/cache" "$SHOREBIRD_ROOT/packages"
  echo "#!/bin/sh" > "$SHOREBIRD_ROOT/bin/shorebird"
  echo "name: x" > "$SHOREBIRD_ROOT/packages/pubspec.yaml"
  echo "bin/cache/" > "$SHOREBIRD_ROOT/.gitignore"
  git -C "$SHOREBIRD_ROOT" init -q
  git -C "$SHOREBIRD_ROOT" add -A
  git -C "$SHOREBIRD_ROOT" -c user.name=t -c user.email=t@example.com commit -q -m init
  REVISION="$(git -C "$SHOREBIRD_ROOT" rev-parse HEAD)"
  STAMP_PATH="$SHOREBIRD_ROOT/bin/cache/shorebird.stamp"
  PREBUILT_PATH="$SHOREBIRD_ROOT/bin/cache/shorebird"
  PREBUILT_STAMP_PATH="$SHOREBIRD_ROOT/bin/cache/shorebird-cli.stamp"
}

failures=0
fail() {
  echo "  ❌ $*"
  failures=$((failures + 1))
}

# Runs install_prebuilt_cli, keeping its output for a failure's report.
install() {
  if install_prebuilt_cli > "$tmp_root/out.log" 2>&1; then
    installed=0
  else
    installed=1
  fi
}

expect_installed() {
  local version="$1"
  [[ "$installed" == 0 ]] || fail "returned non-zero: $(cat "$tmp_root/out.log")"
  [[ "$(cat "$PREBUILT_STAMP_PATH" 2>/dev/null)" == "$REVISION" ]] ||
    fail "shorebird-cli.stamp isn't $REVISION"
  [[ "$("$PREBUILT_PATH" --version 2>&1)" == "Shorebird $version" ]] ||
    fail "bin/cache/shorebird isn't the published $version"
  [[ ! -e "$STAMP_PATH" ]] || fail "shorebird.stamp was left beside the binary's"
  [[ ! -e "$SHOREBIRD_ROOT/bin/cache/shorebird-cli.tmp" ]] || fail "left its download directory"
}

# A fallback: non-zero, and nothing that makes bin/shorebird run a binary.
expect_fallback() {
  [[ "$installed" != 0 ]] || fail "returned 0"
  [[ ! -e "$PREBUILT_STAMP_PATH" ]] || fail "wrote shorebird-cli.stamp"
  [[ ! -e "$PREBUILT_PATH" ]] || fail "left bin/cache/shorebird"
  [[ ! -e "$SHOREBIRD_ROOT/bin/cache/shorebird-cli.tmp" ]] || fail "left its download directory"
  if prebuilt_is_current; then fail "prebuilt_is_current after a fallback"; fi
}

run_case() {
  local before=$failures
  echo "• $1"
  "$2"
  [[ $failures == "$before" ]] && echo "  ✅"
}

case_installs() {
  new_root
  publish_cli 1.2.3
  install
  expect_installed 1.2.3
  prebuilt_is_current || fail "prebuilt_is_current is false"
}

# Every install of a commit with no binaries (main, a branch, a fork) takes
# this path, so it says nothing.
case_404() {
  new_root
  install
  expect_fallback
  [[ ! -s "$tmp_root/out.log" ]] || fail "printed: $(cat "$tmp_root/out.log")"
}

case_zip_missing() {
  new_root
  publish_cli 1.2.3
  rm "$www/shorebird-cli/$REVISION/shorebird-$platform.zip"
  install
  expect_fallback
  grep -q "Couldn't download" "$tmp_root/out.log" || fail "didn't say it couldn't download"
}

case_checksum_mismatch() {
  new_root
  local src="$tmp_root/mismatch"
  fake_cli "$src" 1.2.3
  (cd "$src" && python3 -m zipfile -c "$src.zip" shorebird)
  publish "$src.zip" "$(printf '0%.0s' $(seq 64))"
  install
  expect_fallback
  grep -q "doesn't match its checksum" "$tmp_root/out.log" || fail "didn't say the checksum is wrong"
}

case_corrupt_zip() {
  new_root
  echo "not a zip" > "$tmp_root/corrupt.zip"
  publish "$tmp_root/corrupt.zip"
  install
  expect_fallback
  grep -q "Couldn't unzip" "$tmp_root/out.log" || fail "didn't say it couldn't unzip"
}

case_binary_fails() {
  new_root
  publish_cli 1.2.3 1
  install
  expect_fallback
  grep -q "didn't start" "$tmp_root/out.log" || fail "didn't say the binary didn't start"
}

case_local_changes() {
  local path
  for path in bin/shorebird packages/pubspec.yaml third_party/new_file; do
    new_root
    publish_cli 1.2.3
    mkdir -p "$(dirname "$SHOREBIRD_ROOT/$path")"
    echo "changed" >> "$SHOREBIRD_ROOT/$path"
    install
    echo "  $path:"
    expect_fallback
  done
}

case_unknown_platform() {
  new_root
  publish_cli 1.2.3
  # shellcheck disable=SC2329 # Shadows uname for prebuilt_platform.
  uname() { echo FreeBSD; }
  install
  unset -f uname
  expect_fallback
}

case_upgrade_from_source_build() {
  new_root
  # What a source build of an earlier commit and an earlier binary leave.
  echo "0000000000000000000000000000000000000000" > "$STAMP_PATH"
  fake_cli "$SHOREBIRD_ROOT/bin/cache" 1.0.0
  publish_cli 1.2.3
  install
  expect_installed 1.2.3
}

case_upgrade_from_prebuilt() {
  new_root
  fake_cli "$SHOREBIRD_ROOT/bin/cache" 1.0.0
  echo "0000000000000000000000000000000000000000" > "$PREBUILT_STAMP_PATH"
  publish_cli 1.2.3
  install
  expect_installed 1.2.3
}

# sha256_of takes sha256sum when there is one, which macOS 14 and later have
# too, so its shasum branch runs only with sha256sum hidden: each PATH
# directory holding one is replaced by links to the rest of it.
case_shasum_only() {
  new_root
  publish_cli 1.2.3
  local path="" dir entry farm
  local IFS=:
  for dir in $PATH; do
    if [[ -e "$dir/sha256sum" ]]; then
      farm="$(mktemp -d "$tmp_root/path.XXXXXX")"
      for entry in "$dir"/*; do
        [[ "$(basename "$entry")" == sha256sum ]] || ln -s "$entry" "$farm/"
      done
      dir="$farm"
    fi
    path="${path:+$path:}$dir"
  done
  unset IFS
  PATH="$path" bash -c 'hash sha256sum' 2>/dev/null && fail "sha256sum still on PATH"
  local saved_path="$PATH"
  PATH="$path"
  hash -r
  install
  PATH="$saved_path"
  hash -r
  expect_installed 1.2.3
}

run_case "installs the published CLI" case_installs
run_case "falls back silently on a 404" case_404
run_case "falls back when the zip is missing" case_zip_missing
run_case "falls back on a checksum mismatch" case_checksum_mismatch
run_case "falls back on a corrupt zip" case_corrupt_zip
run_case "falls back when the binary fails --version" case_binary_fails
run_case "falls back with local changes under bin, packages and third_party" case_local_changes
run_case "falls back on a platform with no binary" case_unknown_platform
run_case "upgrades a source-built install" case_upgrade_from_source_build
run_case "upgrades an earlier prebuilt install" case_upgrade_from_prebuilt
if hash shasum 2>/dev/null; then
  run_case "installs with shasum and no sha256sum" case_shasum_only
fi

if [[ $failures != 0 ]]; then
  echo "❌ $failures check(s) failed."
  exit 1
fi
echo "✅ All prebuilt CLI install checks passed."
