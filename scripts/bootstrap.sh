#!/bin/bash

# Fetch dart dependencies
dart pub global activate very_good_cli
very_good --analytics=false
very_good packages get -r ./packages

# And the rust side
cd updater
cargo check