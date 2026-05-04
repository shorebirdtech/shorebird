#!/bin/bash
# Prints help output for releases and patches subcommands.
#
# Usage:
#   ./scripts/print_help.sh
#
# For dev builds:
#   SHOREBIRD="dart run packages/shorebird_cli/bin/shorebird.dart" ./scripts/print_help.sh

SHOREBIRD="${SHOREBIRD:-shorebird}"

header() { echo; echo "━━━ $1 ━━━"; echo; }

header "shorebird releases --help"
$SHOREBIRD releases --help 2>&1

header "shorebird releases list --help"
$SHOREBIRD releases list --help 2>&1

header "shorebird releases info --help"
$SHOREBIRD releases info --help 2>&1

header "shorebird patches --help"
$SHOREBIRD patches --help 2>&1

header "shorebird patches list --help"
$SHOREBIRD patches list --help 2>&1

header "shorebird patches info --help"
$SHOREBIRD patches info --help 2>&1
