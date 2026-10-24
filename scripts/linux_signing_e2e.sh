#!/bin/bash -e

# cspell:words genrsa pubout Xvfb

# End-to-end test of patch signing on Linux: the real CLI against a real
# server, a real Flutter build, and the built app launched headless, checking
# which code it runs after it downloads each patch.
#
# One leg builds two releases of a fresh app and installs each twice, once as
# built (strict: the patch signature is checked at every launch) and once
# with `patch_verification: install_only` added to the installed bundle's
# shorebird.yaml (checked once, at install). That edit is what the CLI writes
# when it builds with that setting; the CLI now refuses to build it on
# engines whose updater skips the check (#4163), but releases made before
# that are on devices, so the test installs it on every engine.
#
#   1.0.0+1  --managed-signing: Shorebird embeds and signs with its own key.
#            Patch: signed by Shorebird.            -> managed_*
#   1.0.0+2  --public-key-path A: the customer's key.
#            Patch 1: signed with key B.            -> wrong_key_*
#            Patch 2: unsigned.                     -> unsigned_*
#            Patch 3: signed with key A.            -> valid_*
#
# Each patch prints its own label, so after each one every install is
# launched twice (download and install, then boot) and the label it prints
# says whether it runs the patch ("applied") or not ("refused"). Each install
# keeps its updater state in its own HOME, so earlier refused patches stay
# marked bad, as on a device.
#
# Results are compared with linux_signing_e2e_expected.txt, one row per
# Flutter version. "xfail" there is a known bug: the patch should be
# refused, and the leg fails if it is (update the table), or if it isn't
# applied either.
#
# Pre-requisites: Linux with the Flutter Linux build dependencies, Xvfb and
# openssl; Shorebird on PATH and signed in (CI signs in with OIDC).
#
# Usage: ./linux_signing_e2e.sh <flutter-version|default>

FLUTTER_VERSION=$1
if [[ -z "$FLUTTER_VERSION" ]]; then
    echo "Usage: $0 <flutter-version|default>"
    exit 64
fi
if [[ "$FLUTTER_VERSION" == "default" ]]; then
    FLUTTER_VERSION_ARGS=()
else
    FLUTTER_VERSION_ARGS=(--flutter-version="$FLUTTER_VERSION")
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
EXPECTED_FILE="$SCRIPT_DIR/linux_signing_e2e_expected.txt"
SHOREBIRD_ROOT=$(dirname "$SCRIPT_DIR")
# The Flutter the CLI pins, for `flutter create`; not the version under test.
FLUTTER="$SHOREBIRD_ROOT/bin/cache/flutter/$(cat "$SHOREBIRD_ROOT/bin/internal/flutter.version")/bin/flutter"

export SHOREBIRD_HOSTED_URL="${SHOREBIRD_HOSTED_URL:-https://api-dev.shorebird.dev}"

# How long one launch may take to finish its update check, or to print its
# label.
UPDATE_WAIT_SECONDS=180
LABEL_WAIT_SECONDS=60

CASES=(managed_strict managed_install_only wrong_key_strict wrong_key_install_only
    unsigned_strict unsigned_install_only valid_strict valid_install_only)

# The expected outcome of [case] for this Flutter version.
expected_for() {
    awk -v version="$FLUTTER_VERSION" -v case_name="$1" '
        /^#/ || NF == 0 { next }
        $1 == "flutter" { for (i = 2; i <= NF; i++) column[$i] = i; next }
        $1 == version { print $(column[case_name]); found = 1 }
        END { if (!found) exit 1 }
    ' "$EXPECTED_FILE"
}

for case_name in "${CASES[@]}"; do
    if ! expected=$(expected_for "$case_name") || [[ -z "$expected" ]]; then
        echo "❌ $EXPECTED_FILE has no '$case_name' result for Flutter $FLUTTER_VERSION."
        exit 1
    fi
done

TIMINGS=()
# Runs a command and records its wall time under [name].
timed() {
    local name=$1
    shift
    local start=$SECONDS
    "$@"
    TIMINGS+=("$name $((SECONDS - start))s")
}

APP_PIDS=()
XVFB_PID=
cleanup() {
    local status=$?
    set +e
    for pid in "${APP_PIDS[@]}"; do kill "$pid" 2>/dev/null; done
    [[ -n "$XVFB_PID" ]] && kill "$XVFB_PID" 2>/dev/null
    # Each leg mints an app; delete it so the e2e account's app list stays
    # flat (see patch_e2e.sh).
    if [[ -n "${APP_ID:-}" ]]; then
        echo "Deleting e2e app $APP_ID"
        shorebird api -X DELETE "apps/$APP_ID" ||
            echo "⚠️  Failed to delete e2e app $APP_ID; it will need pruning."
    fi
    return $status
}
trap cleanup EXIT

WORK=$(mktemp -d -t 'shorebird signing-XXXXX')

Xvfb :99 -screen 0 1024x768x24 >"$WORK/xvfb.log" 2>&1 &
XVFB_PID=$!
export DISPLAY=:99

# Launches [bundle] with HOME=[home], logging to [log], until a line matches
# the extended regex [pattern] or [seconds] pass. Stops the app either way;
# fails if the pattern never appeared.
launch_until() {
    local bundle=$1 home=$2 log=$3 pattern=$4 seconds=$5
    HOME="$home" "$bundle/e2e_test" >"$log" 2>&1 &
    local pid=$!
    APP_PIDS+=("$pid")
    local deadline=$((SECONDS + seconds)) matched=1
    while ((SECONDS < deadline)); do
        if grep -qE "$pattern" "$log"; then
            matched=0
            break
        fi
        if ! kill -0 "$pid" 2>/dev/null; then break; fi
        sleep 1
    done
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    return $matched
}

RESULTS=()
FAILED=0
# Launches the install [bundle] (state in [home]) twice after the patch that
# prints [label] was published: once to download and install it, once to
# boot. Records whether [case_name] ran the patch, against the table.
check_case() {
    local case_name=$1 bundle=$2 home=$3 label=$4
    local log_prefix="$WORK/$case_name"
    local start=$SECONDS
    if ! launch_until "$bundle" "$home" "$log_prefix.update.log" \
        'Update thread finished|Update failed' $UPDATE_WAIT_SECONDS; then
        echo "❌ $case_name: the update check didn't finish within ${UPDATE_WAIT_SECONDS}s."
        cat "$log_prefix.update.log"
        exit 1
    fi
    if ! launch_until "$bundle" "$home" "$log_prefix.boot.log" \
        'signing-e2e: ' $LABEL_WAIT_SECONDS; then
        echo "❌ $case_name: the app printed no label within ${LABEL_WAIT_SECONDS}s."
        cat "$log_prefix.boot.log"
        exit 1
    fi
    local running actual expected verdict
    running=$(grep -oE 'signing-e2e: [a-z-]+' "$log_prefix.boot.log" | head -1)
    running=${running#signing-e2e: }
    if [[ "$running" == "$label" ]]; then actual=applied; else actual=refused; fi
    expected=$(expected_for "$case_name")
    case "$expected/$actual" in
    applied/applied | refused/refused) verdict=PASS ;;
    xfail/applied) verdict="XFAIL (known bug: should be refused)" ;;
    xfail/refused)
        verdict="XPASS: now refused; set it to refused in the table"
        FAILED=1
        ;;
    *)
        verdict=FAIL
        FAILED=1
        ;;
    esac
    RESULTS+=("| $case_name | $expected | $actual (runs $running) | $verdict | $((SECONDS - start))s |")
    echo "$case_name: expected $expected, $actual (runs '$running'): $verdict"
    if [[ "$verdict" == FAIL || "$verdict" == XPASS* ]]; then
        echo "--- update launch log"
        cat "$log_prefix.update.log"
        echo "--- boot launch log"
        cat "$log_prefix.boot.log"
    fi
}

set_label() {
    echo "void main() { print('signing-e2e: $1'); }" >lib/main.dart
}

set_version() {
    sed -i "s/^version: .*/version: $1/" pubspec.yaml
}

# Copies the built bundle to [name]_strict and [name]_install_only.
install_release() {
    local name=$1
    local bundle=build/linux/x64/release/bundle
    cp -r "$bundle" "$WORK/${name}_strict"
    cp -r "$bundle" "$WORK/${name}_install_only"
    printf '\npatch_verification: install_only\n' \
        >>"$WORK/${name}_install_only/data/flutter_assets/shorebird.yaml"
    mkdir -p "$WORK/home_${name}_strict" "$WORK/home_${name}_install_only"
}

# `--managed-signing` until managed signing is the default (step 3349).
MANAGED_ARGS=()
if shorebird release --help | grep -q -- '--managed-signing'; then
    MANAGED_ARGS=(--managed-signing)
fi

PATCH_ARGS=(--allow-asset-diffs --allow-native-diffs -v)

cd "$WORK"
openssl genrsa -out key_a.pem 2048
openssl rsa -in key_a.pem -pubout -out key_a.pub.pem
openssl genrsa -out key_b.pem 2048
openssl rsa -in key_b.pem -pubout -out key_b.pub.pem

timed create "$FLUTTER" create e2e_test --org com.example.e2e_test --empty --platforms linux
cd e2e_test
set_label release
timed init shorebird init --force -v
echo "base_url: $SHOREBIRD_HOSTED_URL" >>shorebird.yaml
APP_ID=$(grep 'app_id:' shorebird.yaml | awk '{print $2}')

set_version 1.0.0+1
timed release_managed shorebird release linux "${FLUTTER_VERSION_ARGS[@]}" "${MANAGED_ARGS[@]}" -v
grep -q patch_public_key build/linux/x64/release/bundle/data/flutter_assets/shorebird.yaml ||
    { echo "❌ The managed release embedded no public key."; exit 1; }
install_release managed

set_version 1.0.0+2
timed release_customer shorebird release linux "${FLUTTER_VERSION_ARGS[@]}" \
    --public-key-path="$WORK/key_a.pub.pem" -v
install_release customer

set_version 1.0.0+1
set_label managed-patch
timed patch_managed shorebird patch linux --release-version=1.0.0+1 "${PATCH_ARGS[@]}"
for mode in strict install_only; do
    timed "check_managed_$mode" check_case "managed_$mode" "$WORK/managed_$mode" \
        "$WORK/home_managed_$mode" managed-patch
done

set_version 1.0.0+2
set_label wrong-key-patch
timed patch_wrong_key shorebird patch linux --release-version=1.0.0+2 "${PATCH_ARGS[@]}" \
    --public-key-path="$WORK/key_b.pub.pem" --private-key-path="$WORK/key_b.pem"
for mode in strict install_only; do
    timed "check_wrong_key_$mode" check_case "wrong_key_$mode" "$WORK/customer_$mode" \
        "$WORK/home_customer_$mode" wrong-key-patch
done

set_label unsigned-patch
timed patch_unsigned shorebird patch linux --release-version=1.0.0+2 "${PATCH_ARGS[@]}"
for mode in strict install_only; do
    timed "check_unsigned_$mode" check_case "unsigned_$mode" "$WORK/customer_$mode" \
        "$WORK/home_customer_$mode" unsigned-patch
done

set_label valid-patch
timed patch_valid shorebird patch linux --release-version=1.0.0+2 "${PATCH_ARGS[@]}" \
    --public-key-path="$WORK/key_a.pub.pem" --private-key-path="$WORK/key_a.pem"
for mode in strict install_only; do
    timed "check_valid_$mode" check_case "valid_$mode" "$WORK/customer_$mode" \
        "$WORK/home_customer_$mode" valid-patch
done

REPORT=$(
    echo "### Patch signing on Linux, Flutter $FLUTTER_VERSION"
    echo
    echo "| Case | Expected | Actual | Result | Time |"
    echo "| --- | --- | --- | --- | --- |"
    printf '%s\n' "${RESULTS[@]}"
    echo
    echo "Wall time by step: $(printf '%s, ' "${TIMINGS[@]}" | sed 's/, $//')"
)
echo "$REPORT"
if [[ -n "$GITHUB_STEP_SUMMARY" ]]; then echo "$REPORT" >>"$GITHUB_STEP_SUMMARY"; fi

if ((FAILED)); then
    echo "❌ Results differ from $EXPECTED_FILE."
    exit 1
fi
echo "✅ All results match $EXPECTED_FILE."
