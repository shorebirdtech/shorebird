import 'package:artifact_proxy/artifact_proxy.dart';

/// The proxy configuration used by the server.
const config = ProxyConfig(
  engineMappings: {
    ...flutter_3_7_10,
    ...flutter_3_7_8,
  },
);

// On the assumption artifact layouts don't change very often for Flutter.
// ignore: camel_case_types
class _EngineMapping3_7 extends EngineMapping {
  const _EngineMapping3_7({
    required super.flutterEngineRevision,
  }) : super(
          shorebirdStorageBucket: 'download.shorebird.dev',
          shorebirdArtifactOverrides: const {
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
        );
}

/// Flutter 3.7.10
const flutter_3_7_10 = {
  // Attempt to fix https://github.com/shorebirdtech/shorebird/issues/235
  'f68335f3f6afdb1595420b1c3b5a16c8da75a1cf': _EngineMapping3_7(
    flutterEngineRevision: 'ec975089acb540fc60752606a3d3ba809dd1528b',
  ),
  '978a56f2d97f9ce24a2b6bc22c9bbceaaba0343c': _EngineMapping3_7(
    flutterEngineRevision: 'ec975089acb540fc60752606a3d3ba809dd1528b',
  ),
  '7aa5c44764e10722d188ece75819f7d10f5269a3': _EngineMapping3_7(
    flutterEngineRevision: 'ec975089acb540fc60752606a3d3ba809dd1528b',
  ),
};

/// Flutter 3.7.8
const flutter_3_7_8 = {
  '79f4c5321a581f580a9bda01ec372cbf4a53aa53': _EngineMapping3_7(
    flutterEngineRevision: '9aa7816315095c86410527932918c718cb35e7d6',
  ),
};
