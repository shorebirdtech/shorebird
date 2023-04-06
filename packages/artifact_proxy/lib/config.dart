import 'package:artifact_proxy/artifact_proxy.dart';

/// The proxy configuration used by the server.
const config = ProxyConfig(
  engineMappings: {
    ...flutter_3_7_8,
  },
);

/// Flutter 3.7.8
const flutter_3_7_8 = {
  '79f4c5321a581f580a9bda01ec372cbf4a53aa53': EngineMapping(
    flutterEngineRevision: '9aa7816315095c86410527932918c718cb35e7d6',
    shorebirdStorageBucket: 'download.shorebird.dev',
    shorebirdArtifactOverrides: {
      // artifacts.zip
      r'flutter_infra_release/flutter/$engine/android-arm-64-release/artifacts.zip',
      r'flutter_infra_release/flutter/$engine/android-arm-release/artifacts.zip',
      r'flutter_infra_release/flutter/$engine/android-x64-release/artifacts.zip',

      // embedding release
      r'download.flutter.io/io/flutter/flutter_embedding_release/1.0.0-$engine/flutter_embedding_release-1.0.0-$engine.pom',
      r'download.flutter.io/io/flutter/flutter_embedding_release/1.0.0-$engine/flutter_embedding_release-1.0.0-$engine.jar',

      // arm64_v8a release
      r'download.flutter.io/io/flutter/arm64_v8a_release/1.0.0-$engine/arm64_v8a_release-1.0.0-$engine.pom',
      r'download.flutter.io/io/flutter/arm64_v8a_release/1.0.0-$engine/arm64_v8a_release-1.0.0-$engine.jar',

      // armeabi_v7a release
      r'download.flutter.io/io/flutter/armeabi_v7a_release/1.0.0-$engine/armeabi_v7a_release-1.0.0-$engine.pom',
      r'download.flutter.io/io/flutter/armeabi_v7a_release/1.0.0-$engine/armeabi_v7a_release-1.0.0-$engine.jar',

      // x86_64 release
      r'download.flutter.io/io/flutter/x86_64_release/1.0.0-$engine/x86_64_release-1.0.0-$engine.pom',
      r'download.flutter.io/io/flutter/x86_64_release/1.0.0-$engine/x86_64_release-1.0.0-$engine.jar',
    },
  ),
};
