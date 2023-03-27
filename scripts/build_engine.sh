#!/bin/sh -e

# Given a path to a Flutter engine, generate a shorebird version of it.
# This is done by removing all the files that are not needed for the
# Flutter engine to run.
# Currently, only the android arm64 release version of the engine is supported.
#
# Usage:
# ./build_engine <path-to-engine> <output-directory>

# The path to the shorebird checkout.
SHOREBIRD_PATH=$(dirname $(dirname $(realpath $0)))

# The path to the Flutter engine.
ENGINE_PATH=$(realpath $1)

# The path where the shorebird engine will be generated.
OUTPUT_PATH=$2

if [[ "$OUTPUT_PATH" = /* ]]
then
   : # Absolute path
else
   :
    echo "Output path must be absolute"
    exit 1
fi

echo "Building engine from $ENGINE_PATH to $OUTPUT_PATH"

# Assume cargo-ndk is already installed:
# cargo install cargo-ndk

# Assume the toolchains are already installed
# rustup target add \
#     aarch64-linux-android \
#     armv7-linux-androideabi \
#     x86_64-linux-android \
#     i686-linux-android

# Build the Rust library.
cd $SHOREBIRD_PATH/updater/library
# Build both the arm64 and armv7 versions of the library.
cargo ndk \
  --target aarch64-linux-android \
  --target armv7-linux-androideabi \
  build --release

# We assume the engine has symlinks set up for now (we should not rely on this).

# Build the patch tool.
cd $SHOREBIRD_PATH/updater/patch
cargo build --release

# Build the engine
cd $ENGINE_PATH

# Build the engine in release mode for android arm64.
./src/flutter/tools/gn --android --android-cpu=arm64 --runtime-mode=release --no-goma
ninja -C ./src/out/android_release_arm64

# Build the the host_release output.
./src/flutter/tools/gn --runtime-mode=release --no-goma
ninja -C ./src/out/host_release

# List of all files to keep.
KEEP_FILES=(
  "out/android_release_arm64/libflutter.so"
  "out/android_release_arm64/arm64_v8a_release.pom"
  "out/android_release_arm64/flutter_embedding_release.jar"
  "out/android_release_arm64/flutter_patched_sdk/platform_strong.dill"
  "out/android_release_arm64/clang_arm64/impellerc"
  "out/android_release_arm64/clang_arm64/gen_snapshot_arm64"
  "out/android_release_arm64/clang_arm64/gen_snapshot"
  "out/android_release_arm64/arm64_v8a_release.jar"
  "out/android_release_arm64/flutter_embedding_release.pom"
  "out/android_release_arm64/flutter_embedding_release.maven-metadata.xml"
  "out/android_release_arm64/flutter_embedding_release-sources.jar"
  "out/android_release_arm64/arm64_v8a_release.maven-metadata.xml"  
  "out/host_release/gen/const_finder.dart.snapshot"
  "out/host_release/font-subset"
  "flutter/prebuilts/macos-x64/dart-sdk/LICENSE"
  "flutter/prebuilts/macos-x64/dart-sdk/bin/dartaotruntime"
  "flutter/prebuilts/macos-x64/dart-sdk/bin/snapshots/analysis_server.dart.snapshot"
  "flutter/prebuilts/macos-x64/dart-sdk/bin/snapshots/kernel-service.dart.snapshot"
  "flutter/prebuilts/macos-x64/dart-sdk/bin/snapshots/gen_kernel.dart.snapshot"
  "flutter/prebuilts/macos-x64/dart-sdk/bin/snapshots/dartdevc.dart.snapshot"
  "flutter/prebuilts/macos-x64/dart-sdk/bin/snapshots/dart2js.dart.snapshot"
  "flutter/prebuilts/macos-x64/dart-sdk/bin/snapshots/dartdev.dart.snapshot"
  "flutter/prebuilts/macos-x64/dart-sdk/bin/snapshots/kernel_worker.dart.snapshot"
  "flutter/prebuilts/macos-x64/dart-sdk/bin/snapshots/dartdev.dill"
  "flutter/prebuilts/macos-x64/dart-sdk/bin/snapshots/frontend_server.dart.snapshot"
  # "flutter/prebuilts/macos-x64/dart-sdk/bin/snapshots/dart2wasm_product.snapshot"
  "flutter/prebuilts/macos-x64/dart-sdk/bin/snapshots/dds.dart.snapshot"
  "flutter/prebuilts/macos-x64/dart-sdk/bin/dart"
  "flutter/prebuilts/macos-x64/dart-sdk/bin/utils/gen_snapshot"
  "flutter/prebuilts/macos-x64/dart-sdk/README"
  "flutter/prebuilts/macos-x64/dart-sdk/version"
  "flutter/prebuilts/macos-x64/dart-sdk/revision"
)

cd -

TEMP_DIR=`mktemp -d`

# Copy all files to temp directory.
for file in "${KEEP_FILES[@]}"
do
  mkdir -p $TEMP_DIR/$(dirname $file)
  cp -r $ENGINE_PATH/src/$file $TEMP_DIR/$file
done

cp $SHOREBIRD_PATH/updater/target/release/patch $TEMP_DIR/patch

cd $TEMP_DIR

# Zip the output.
zip -r -X engine.zip *

cd -

# Create the output directory.
mkdir -p $OUTPUT_PATH
cp $TEMP_DIR/engine.zip $OUTPUT_PATH/engine.zip

# Clean up.
rm -rf $TEMP_DIR
