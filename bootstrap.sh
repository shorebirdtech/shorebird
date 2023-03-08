#!/bin/bash

# We could do something much fancier here.

# Fetch dart dependencies
cd packages/shorebird_cli
dart pub get
cd ../..

cd packages/shorebird_code_push_api
dart pub get
cd ../..

cd packages/shorebird_code_push_api_client
dart pub get
cd ../..

cd updater/dart_bindings
dart pub get
cd ../..

cd updater/dart_cli
dart pub get
cd ../..

# And the rust side
cd updater
cargo check