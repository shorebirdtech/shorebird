#!/usr/bin/env bash
#
# Repro for shorebirdtech/shorebird#3388 — "every requested architecture was
# missing" on Flutter 3.44+ Android releases.
#
# Background: Flutter 3.44 (flutter/flutter#181275) handed libapp.so stripping
# to AGP. When AGP produces no stripped libapp.so — a legacy
# `keepDebugSymbols.add("**/libapp.so")` line, a gen_snapshot --strip pre-strip,
# or the upstream strip-handover bug — `stripped_native_libs/.../out/lib` is
# empty for libapp.so even though the library is still bundled into the AAB.
# Shorebird reads libapp.so from that empty directory and fails.
#
# The drafted fix falls back to `merged_native_libs`. That is only correct if
# its bytes match what is packaged into the AAB (and shipped to the device);
# otherwise patches fail at runtime with link_failure. This script proves it
# two ways:
#
#   Tier 1 (byte-match gate, no device): reproduce the failure, then sha256
#     the AAB's base/lib/<arch>/libapp.so against the stripped and merged
#     copies and report which intermediate is byte-correct.
#
#   Tier 2 (patch-apply, needs a device + the PATCHED CLI): release, install,
#     patch a Dart change, relaunch, and confirm the patch boots with no
#     link_failure. This is the only end-to-end proof of byte-correctness.
#
# Triggers:
#   - keepDebugSymbols (default): injects the legacy line — the most common
#     real-world cause and the validated #2150 case.
#   - obfuscate (OBFUSCATE=1): builds with --obfuscate. On 3.44 the CLI
#     suppresses gen_snapshot --strip, so this should now SUCCEED; it is here
#     as regression coverage and to run the byte-match gate on the stripped
#     path. Combine with INJECT_KEEPDEBUG=1 to exercise both at once.
#
# Usage:
#   # Tier 1 against an existing app:
#   APP_DIR=/path/to/app FLAVOR=internal scripts/repro_libapp_strip_3388.sh
#
#   # Tier 1 + Tier 2 on a device, creating a throwaway app, patched CLI:
#   CREATE_APP=1 TIER2=1 SHOREBIRD=./bin/shorebird DEVICE_ID=57211FDCH005Z2 \
#     scripts/repro_libapp_strip_3388.sh
#
#   # Obfuscated regression run:
#   CREATE_APP=1 TIER2=1 OBFUSCATE=1 INJECT_KEEPDEBUG=0 \
#     SHOREBIRD=./bin/shorebird scripts/repro_libapp_strip_3388.sh
#
# Env:
#   APP_DIR            existing shorebird app dir (required unless CREATE_APP=1)
#   CREATE_APP=0|1     create a throwaway `flutter create` + `shorebird init` app
#   FLAVOR             optional product flavor
#   OBFUSCATE=0|1      build with --obfuscate (+ --split-debug-info)
#   INJECT_KEEPDEBUG=1 inject the keepDebugSymbols trigger (default 1)
#   TIER2=0|1          run the on-device patch-apply test (default 0)
#   SHOREBIRD          CLI under test (default: ./bin/shorebird if present)
#   ADB                adb path (default: adb on PATH, else SDK platform-tools)
#   DEVICE_ID          adb device serial (default: the only connected device)
#   KEEP_GRADLE_EDIT=1 leave the injected line in place on exit
#   TIMEOUT_S          per-preview signal wait (default 240)
#
# Exit codes:
#   0  failure reproduced AND merged byte-matches the AAB (and, if TIER2, the
#      patch applied on device) -> ship the fix
#   2  reproduced BUT merged does NOT match the AAB -> switch to AAB extraction
#   3  failure did NOT reproduce (AGP stripped normally — wrong trigger/toolchain)
#   4  Tier 2 failed: release/patch did not boot, or link_failure on device
#   1  setup/usage error

set -uo pipefail

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------
bold() { printf '\033[1m%s\033[0m\n' "$*"; }
info() { printf '  %s\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
err()  { printf '  \033[31m✗\033[0m %s\n' "$*"; }
hr()   { printf -- '----------------------------------------------------------------\n'; }
die()  { err "$*"; exit 1; }

sha256() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}';
  else sha256sum "$1" | awk '{print $1}'; fi
}
sha256_stream() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 | awk '{print $1}';
  else sha256sum | awk '{print $1}'; fi
}

# Read stdin lines into the array named by $1 (bash 3.2 has no `mapfile`).
read_into() {
  local __name="$1" __line
  eval "$__name=()"
  while IFS= read -r __line; do eval "$__name+=(\"\$__line\")"; done
}

# Stream a command's output to a log file in the background; return its PID.
# $1 = logfile, rest = command.
stream_to() {
  local logf="$1"; shift
  : >"$logf"
  ( "$@" >>"$logf" 2>&1 ) &
  echo $!
}

# Wait until $2 (a regex) appears in growing file $1, or $3 seconds elapse.
# Returns 0 on match, 1 on timeout.
wait_for_signal() {
  local logf="$1" pat="$2" timeout="$3" waited=0
  while [ "$waited" -lt "$timeout" ]; do
    if grep -qE "$pat" "$logf" 2>/dev/null; then return 0; fi
    sleep 2; waited=$((waited + 2))
  done
  return 1
}

# ----------------------------------------------------------------------------
# Config
# ----------------------------------------------------------------------------
APP_DIR="${APP_DIR:-}"
CREATE_APP="${CREATE_APP:-0}"
FLAVOR="${FLAVOR:-}"
OBFUSCATE="${OBFUSCATE:-0}"
INJECT_KEEPDEBUG="${INJECT_KEEPDEBUG:-1}"
TIER2="${TIER2:-0}"
KEEP_GRADLE_EDIT="${KEEP_GRADLE_EDIT:-0}"
TIMEOUT_S="${TIMEOUT_S:-240}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SHOREBIRD="${SHOREBIRD:-}"
if [ -z "$SHOREBIRD" ]; then
  if [ -x "$REPO_ROOT/bin/shorebird" ]; then SHOREBIRD="$REPO_ROOT/bin/shorebird";
  else SHOREBIRD="shorebird"; fi
fi

ADB="${ADB:-}"
if [ -z "$ADB" ]; then
  if command -v adb >/dev/null 2>&1; then ADB="adb";
  elif [ -x "$HOME/Library/Android/sdk/platform-tools/adb" ]; then ADB="$HOME/Library/Android/sdk/platform-tools/adb";
  else ADB="adb"; fi
fi

# Canonicalize path-form executables to absolute so they survive the `cd` into
# the app dir. Bare command names (resolved via PATH) are left alone.
abspath_cmd() {
  case "$1" in
    */*) printf '%s/%s\n' "$(cd "$(dirname "$1")" && pwd)" "$(basename "$1")";;
    *)   printf '%s\n' "$1";;
  esac
}
SHOREBIRD="$(abspath_cmd "$SHOREBIRD")"
ADB="$(abspath_cmd "$ADB")"

GRADLE_LINE='    packaging.jniLibs.keepDebugSymbols.add("**/libapp.so")'
MARKER='// repro_libapp_strip_3388 injected'
WORKMARKER='REPRO_3388_MARKER'   # the print string we patch

GRADLE_BACKUP=""
cleanup() {
  if [ -n "$GRADLE_BACKUP" ] && [ -f "$GRADLE_BACKUP" ]; then
    if [ "$KEEP_GRADLE_EDIT" = "1" ]; then
      info "KEEP_GRADLE_EDIT=1: leaving injected line; backup at $GRADLE_BACKUP"
    else
      mv -f "$GRADLE_BACKUP" "$GRADLE_FILE"; info "restored $GRADLE_FILE"
    fi
  fi
}
trap cleanup EXIT

# ----------------------------------------------------------------------------
# 0. Toolchain
# ----------------------------------------------------------------------------
bold "0. Toolchain"
command -v "$SHOREBIRD" >/dev/null 2>&1 || [ -x "$SHOREBIRD" ] || die "shorebird not found: $SHOREBIRD"
command -v unzip >/dev/null 2>&1 || die "unzip not found"
: "${ANDROID_HOME:=${ANDROID_SDK_ROOT:-}}"
[ -n "${ANDROID_HOME:-}" ] && [ -d "${ANDROID_HOME:-}" ] \
  && ok "Android SDK: $ANDROID_HOME" || warn "ANDROID_HOME unset — gradle may not find the SDK"
info "shorebird: $("$SHOREBIRD" --version 2>/dev/null | head -1)"
FLUTTER_LINE="$("$SHOREBIRD" --version 2>/dev/null | grep -i '^Flutter' || true)"
info "${FLUTTER_LINE:-Flutter: unknown}"
case "$FLUTTER_LINE" in
  *3.4[4-9]*|*3.[5-9][0-9]*|*[4-9].*) ok "Flutter is 3.44+";;
  *) warn "Flutter does not look 3.44+; this targets the 3.44 strip handover";;
esac
if [ "$TIER2" = "1" ]; then
  command -v "$ADB" >/dev/null 2>&1 || [ -x "$ADB" ] || die "adb not found: $ADB"
  if [ -z "${DEVICE_ID:-}" ]; then
    DEVICE_ID="$("$ADB" devices | awk 'NR>1 && $2=="device"{print $1; exit}')"
  fi
  [ -n "${DEVICE_ID:-}" ] || die "TIER2=1 but no connected adb device (state 'device')"
  ok "device: $DEVICE_ID"
fi

# ----------------------------------------------------------------------------
# 1. Prepare app
# ----------------------------------------------------------------------------
bold "1. Prepare app"
if [ "$CREATE_APP" = "1" ]; then
  command -v flutter >/dev/null 2>&1 || die "CREATE_APP=1 needs flutter on PATH"
  WORK="$(mktemp -d -t 'repro3388-XXXXX')"
  info "creating throwaway app in $WORK"
  ( cd "$WORK" && flutter create e2e --org dev.shorebird.repro3388 --empty --platforms android >/dev/null )
  APP_DIR="$WORK/e2e"
  cat >"$APP_DIR/lib/main.dart" <<EOF
void main() {
  print('$WORKMARKER hello world');
}
EOF
  ( cd "$APP_DIR" && "$SHOREBIRD" init --force -v >/dev/null )
  # Ensure a debug keystore exists (needed to install on device in CI-like envs).
  if [ ! -f "$HOME/.android/debug.keystore" ]; then
    keytool -genkey -v -keystore "$HOME/.android/debug.keystore" -keyalg RSA \
      -keysize 2048 -validity 10000 -alias AndroidDebugKey -storepass android \
      -keypass android -dname "CN=Android Debug,O=Android,C=US" >/dev/null 2>&1 || true
  fi
  ok "created app at $APP_DIR"
else
  [ -n "$APP_DIR" ] || die "set APP_DIR (or CREATE_APP=1)"
  [ -d "$APP_DIR/android/app" ] || die "APP_DIR has no android/app: $APP_DIR"
fi

GRADLE_FILE="$APP_DIR/android/app/build.gradle.kts"
[ -f "$GRADLE_FILE" ] || GRADLE_FILE="$APP_DIR/android/app/build.gradle"
[ -f "$GRADLE_FILE" ] || die "no android/app/build.gradle(.kts) in $APP_DIR"
APP_ID="$(grep 'app_id:' "$APP_DIR/shorebird.yaml" 2>/dev/null | awk '{print $2}')"
info "app dir: $APP_DIR"
info "app_id:  ${APP_ID:-<none>}"

# ----------------------------------------------------------------------------
# 2. Inject the failure trigger
# ----------------------------------------------------------------------------
bold "2. Trigger"
if [ "$INJECT_KEEPDEBUG" = "1" ]; then
  if grep -q 'keepDebugSymbols' "$GRADLE_FILE"; then
    ok "build.gradle already references keepDebugSymbols — using as-is"
    GRADLE_BACKUP="$GRADLE_FILE.repro-backup"; cp "$GRADLE_FILE" "$GRADLE_BACKUP"
  else
    GRADLE_BACKUP="$GRADLE_FILE.repro-backup"; cp "$GRADLE_FILE" "$GRADLE_BACKUP"
    awk -v line="$GRADLE_LINE" -v marker="$MARKER" '
      { print }
      /^android[[:space:]]*\{/ && !done { print "    " marker; print line; done=1 }
    ' "$GRADLE_BACKUP" > "$GRADLE_FILE"
    grep -q 'keepDebugSymbols' "$GRADLE_FILE" || die "failed to inject (no 'android {' block)"
    ok "injected keepDebugSymbols line"
  fi
else
  info "INJECT_KEEPDEBUG=0: not injecting keepDebugSymbols"
fi
[ "$OBFUSCATE" = "1" ] && ok "OBFUSCATE=1: building with --obfuscate" || info "OBFUSCATE=0"

# ----------------------------------------------------------------------------
# 3. Release
# ----------------------------------------------------------------------------
bold "3. shorebird release android"
( cd "$APP_DIR" && "$SHOREBIRD" cache clean >/dev/null 2>&1 || true )
REL_ARGS=(release android --verbose)
[ -n "$FLAVOR" ] && REL_ARGS+=(--flavor "$FLAVOR")
if [ "$OBFUSCATE" = "1" ]; then
  REL_ARGS+=(--obfuscate --split-debug-info=./build/symbols)
fi
info "running: $SHOREBIRD ${REL_ARGS[*]}"
REL_LOG="$(mktemp)"
( cd "$APP_DIR" && "$SHOREBIRD" "${REL_ARGS[@]}" ) >"$REL_LOG" 2>&1 </dev/null
REL_RC=$?
info "release exit code: $REL_RC"
REPRODUCED=0; RELEASED=0
if grep -qiE 'every requested architecture was missing|No architecture artifacts found' "$REL_LOG"; then
  ok "reproduced the missing-arch upload failure"; REPRODUCED=1
elif [ "$REL_RC" -eq 0 ]; then
  ok "release SUCCEEDED"; RELEASED=1
else
  warn "release failed for another reason — see tail"
fi
RELEASE_VERSION="$(grep -oE 'Release version: [0-9][^ ]*' "$REL_LOG" | head -1 | awk '{print $3}')"
[ -z "$RELEASE_VERSION" ] && RELEASE_VERSION="$(grep -oE 'release-version[ =][0-9][^ ]*' "$REL_LOG" | head -1 | grep -oE '[0-9][^ ]*')"
info "release version: ${RELEASE_VERSION:-<unknown>}"
info "release log tail:"; tail -n 12 "$REL_LOG" | sed 's/^/      /'

# ----------------------------------------------------------------------------
# 4. Locate intermediates + AAB
# ----------------------------------------------------------------------------
bold "4. Build outputs"
BUILD="$APP_DIR/build/app"
read_into STRIPPED_LIBS < <(find "$BUILD/intermediates/stripped_native_libs" -name libapp.so 2>/dev/null | sort)
read_into MERGED_LIBS   < <(find "$BUILD/intermediates/merged_native_libs"   -name libapp.so 2>/dev/null | sort)
info "stripped_native_libs libapp.so: ${#STRIPPED_LIBS[@]}"
[ "${#STRIPPED_LIBS[@]}" -eq 0 ] && ok "stripped has NO libapp.so (failure mode)" || info "stripped has libapp.so (AGP stripped)"
info "merged_native_libs libapp.so: ${#MERGED_LIBS[@]}"
[ "${#MERGED_LIBS[@]}" -gt 0 ] && ok "merged HAS libapp.so (fallback target)" || warn "merged has NO libapp.so"
AAB="$(find "$BUILD/outputs/bundle" -name '*.aab' 2>/dev/null | sort | tail -1)"
[ -n "$AAB" ] || die "no .aab under $BUILD/outputs/bundle"
info "aab: $AAB"

# ----------------------------------------------------------------------------
# 5. Byte-match gate
# ----------------------------------------------------------------------------
bold "5. Byte-match gate (AAB vs intermediates)"
read_into AAB_ARCHS < <(unzip -Z1 "$AAB" 2>/dev/null \
  | grep -oE 'base/lib/[^/]+/libapp\.so' | sed -E 's#base/lib/([^/]+)/libapp.so#\1#' | sort -u)
[ "${#AAB_ARCHS[@]}" -gt 0 ] || die "no base/lib/<arch>/libapp.so in the AAB"
MERGED_OK=1; MERGED_ANY=0
printf '  %-14s %-12s %-10s %-10s\n' arch aab stripped merged; hr
for arch in "${AAB_ARCHS[@]}"; do
  aab_hash="$(unzip -p "$AAB" "base/lib/$arch/libapp.so" 2>/dev/null | sha256_stream)"
  s_path="$(printf '%s\n' "${STRIPPED_LIBS[@]:-}" | grep "/$arch/libapp.so" | head -1)"
  m_path="$(printf '%s\n' "${MERGED_LIBS[@]:-}"   | grep "/$arch/libapp.so" | head -1)"
  s_tag="absent"; [ -n "$s_path" ] && { [ "$(sha256 "$s_path")" = "$aab_hash" ] && s_tag="MATCH" || s_tag="DIFFER"; }
  m_tag="absent"
  if [ -n "$m_path" ]; then MERGED_ANY=1; [ "$(sha256 "$m_path")" = "$aab_hash" ] && m_tag="MATCH" || { m_tag="DIFFER"; MERGED_OK=0; }
  else MERGED_OK=0; fi
  printf '  %-14s %-12s %-10s %-10s\n' "$arch" "${aab_hash:0:10}" "$s_tag" "$m_tag"
done
hr

# ----------------------------------------------------------------------------
# 6. Tier 2 — on-device patch apply
# ----------------------------------------------------------------------------
TIER2_RESULT="skipped"
if [ "$TIER2" = "1" ]; then
  bold "6. Tier 2 — patch apply on $DEVICE_ID"
  if [ "$RELEASED" -ne 1 ]; then
    err "release did not succeed — Tier 2 needs the PATCHED CLI (SHOREBIRD=./bin/shorebird)"
    TIER2_RESULT="blocked"
  elif [ -z "$RELEASE_VERSION" ] || [ -z "${APP_ID:-}" ]; then
    err "missing release version or app_id — cannot drive preview"
    TIER2_RESULT="blocked"
  else
    PREV_ARGS=(preview --release-version "$RELEASE_VERSION" --app-id "$APP_ID" --platform android --device-id "$DEVICE_ID" -v)
    [ -n "$FLAVOR" ] && PREV_ARGS+=(--flavor "$FLAVOR")

    info "installing + launching release $RELEASE_VERSION ..."
    PLOG="$(mktemp)"; PID="$(stream_to "$PLOG" "$SHOREBIRD" "${PREV_ARGS[@]}")"
    if wait_for_signal "$PLOG" "$WORKMARKER hello world" "$TIMEOUT_S"; then
      ok "release booted (saw '$WORKMARKER hello world')"
    else
      err "release did not print the marker within ${TIMEOUT_S}s"; tail -n 15 "$PLOG" | sed 's/^/      /'
      TIER2_RESULT="fail"
    fi
    kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null

    if [ "$TIER2_RESULT" != "fail" ]; then
      info "editing lib/main.dart and creating a patch ..."
      sed -i.bak "s/$WORKMARKER hello world/$WORKMARKER hello shorebird/" "$APP_DIR/lib/main.dart"
      PATCH_ARGS=(patch android --release-version "$RELEASE_VERSION" --verbose)
      [ -n "$FLAVOR" ] && PATCH_ARGS+=(--flavor "$FLAVOR")
      [ "$OBFUSCATE" = "1" ] && PATCH_ARGS+=(--obfuscate --split-debug-info=./build/symbols)
      PATCH_LOG="$(mktemp)"
      ( cd "$APP_DIR" && "$SHOREBIRD" "${PATCH_ARGS[@]}" ) >"$PATCH_LOG" 2>&1 </dev/null
      PATCH_RC=$?
      if grep -qiE 'link_failure|differing VM sections' "$PATCH_LOG"; then
        err "PATCH BUILD reported link_failure — base/patch snapshots diverged"
        grep -iE 'link_failure|differing VM sections' "$PATCH_LOG" | head | sed 's/^/      /'
        TIER2_RESULT="fail"
      elif [ "$PATCH_RC" -ne 0 ]; then
        err "patch failed (rc=$PATCH_RC)"; tail -n 15 "$PATCH_LOG" | sed 's/^/      /'
        TIER2_RESULT="fail"
      else
        ok "patch uploaded"
        info "relaunching to boot the patch ..."
        PLOG2="$(mktemp)"; PID2="$(stream_to "$PLOG2" "$SHOREBIRD" "${PREV_ARGS[@]}")"
        if wait_for_signal "$PLOG2" "Patch [0-9]+ successfully" "$TIMEOUT_S"; then
          ok "patch installed on device (saw 'Patch N successfully')"
          # Confirm the patched code actually runs and no link_failure surfaced.
          if grep -qE "link_failure" "$PLOG2"; then
            err "link_failure appeared in device logs after patch"; TIER2_RESULT="fail"
          else
            TIER2_RESULT="pass"
          fi
        else
          err "patch did not boot within ${TIMEOUT_S}s"; tail -n 20 "$PLOG2" | sed 's/^/      /'
          TIER2_RESULT="fail"
        fi
        kill "$PID2" 2>/dev/null; wait "$PID2" 2>/dev/null
      fi
    fi
  fi
  info "Tier 2 result: $TIER2_RESULT"
fi

# ----------------------------------------------------------------------------
# Verdict
# ----------------------------------------------------------------------------
bold "Verdict"
if [ "$REPRODUCED" -ne 1 ] && [ "${#STRIPPED_LIBS[@]}" -gt 0 ] && [ "$INJECT_KEEPDEBUG" = "1" ]; then
  err "Failure did NOT reproduce — AGP stripped libapp.so normally."
  info "Confirm Flutter is 3.44+ and the keepDebugSymbols line took effect."
  exit 3
fi
if [ "$TIER2" = "1" ] && [ "$TIER2_RESULT" != "pass" ] && [ "$TIER2_RESULT" != "skipped" ]; then
  err "Tier 2 did not pass (result: $TIER2_RESULT)."
  info "The patch must boot on device with no link_failure to prove byte-correctness."
  exit 4
fi
if [ "$MERGED_ANY" -eq 1 ] && [ "$MERGED_OK" -eq 1 ]; then
  ok "merged_native_libs byte-MATCHES the AAB for every arch."
  [ "$TIER2_RESULT" = "pass" ] && ok "patch applied on device with no link_failure."
  info "=> Ship the dir-fallback fix."
  exit 0
fi
err "merged_native_libs does NOT match the AAB for every arch."
info "=> Switch the fix to extracting base/lib/<arch>/libapp.so from the AAB."
exit 2
