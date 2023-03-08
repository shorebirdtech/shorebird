#! /bin/sh -x

# Given a path to a Flutter engine, generate a shorebird version of it.
# This is done by removing all the files that are not needed for the
# Flutter engine to run.
# Currently, only the android arm64 release version of the engine is supported.
#
# Usage:
# ./build_engine <path-to-engine> <output-directory>

# The path to the Flutter engine.
ENGINE_PATH=$1

# The path where the shorebird engine will be generated.
OUTPUT_PATH=$2

# Build the engine in release mode for android arm64.
$ENGINE_PATH/src/flutter/tools/gn --android --android-cpu arm64 --runtime-mode=release
ninja -C $ENGINE_PATH/src/out/android_release_arm64

# Build the the host_release output.
$ENGINE_PATH/src/flutter/tools/gn --runtime-mode release
ninja -C $ENGINE_PATH/src/out/host_release

# List of all files to keep.
KEEP_FILES=(
  "out/android_release_arm64/libflutter.so"
  "out/android_release_arm64/arm64_v8a_release.pom"
  "out/android_release_arm64/flutter_embedding_release.jar"
  "out/android_release_arm64/flutter_patched_sdk/platform_strong.dill"
  "out/android_release_arm64/clang_x64/impellerc"
  "out/android_release_arm64/clang_x64/gen_snapshot_arm64"
  "out/android_release_arm64/clang_x64/gen_snapshot"
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
  "flutter/prebuilts/macos-x64/dart-sdk/bin/snapshots/dart2wasm_product.snapshot"
  "flutter/prebuilts/macos-x64/dart-sdk/bin/snapshots/dds.dart.snapshot"
  "flutter/prebuilts/macos-x64/dart-sdk/bin/dart"
  "flutter/prebuilts/macos-x64/dart-sdk/bin/utils/gen_snapshot"
  "flutter/prebuilts/macos-x64/dart-sdk/README"
  "flutter/prebuilts/macos-x64/dart-sdk/version"
  "flutter/prebuilts/macos-x64/dart-sdk/revision"
)

# Copy all files to keep to the output path.
mkdir -p $OUTPUT_PATH

for file in "${KEEP_FILES[@]}"
do
  mkdir -p $OUTPUT_PATH/$(dirname $file)
  cp -r $ENGINE_PATH/src/$file $OUTPUT_PATH/$file
done
