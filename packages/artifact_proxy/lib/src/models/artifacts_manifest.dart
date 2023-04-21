import 'package:json_annotation/json_annotation.dart';

part 'artifacts_manifest.g.dart';

/// {@template engine_mapping}
/// Contains all the information needed to proxy requests for a specific
/// shorebird engine revision.
///
/// Sample `artifacts_manifest.yaml`:
///
/// ```yaml
/// flutter_engine_revision: ec975089acb540fc60752606a3d3ba809dd1528b
/// storage_bucket: download.shorebird.dev
/// artifact_overrides:
///   # artifacts.zip
///   - flutter_infra_release/flutter/$engine/android-arm-64-release/artifacts.zip
///   - flutter_infra_release/flutter/$engine/android-arm-release/artifacts.zip
///   - flutter_infra_release/flutter/$engine/android-x64-release/artifacts.zip
///   # embedding release
///   - download.flutter.io/io/flutter/flutter_embedding_release/1.0.0-$engine/flutter_embedding_release-1.0.0-$engine.pom
///   - download.flutter.io/io/flutter/flutter_embedding_release/1.0.0-$engine/flutter_embedding_release-1.0.0-$engine.jar
///   # arm64_v8a release
///   - download.flutter.io/io/flutter/arm64_v8a_release/1.0.0-$engine/arm64_v8a_release-1.0.0-$engine.pom
///   - download.flutter.io/io/flutter/arm64_v8a_release/1.0.0-$engine/arm64_v8a_release-1.0.0-$engine.jar
///   # armeabi_v7a release
///   - download.flutter.io/io/flutter/armeabi_v7a_release/1.0.0-$engine/armeabi_v7a_release-1.0.0-$engine.pom
///   - download.flutter.io/io/flutter/armeabi_v7a_release/1.0.0-$engine/armeabi_v7a_release-1.0.0-$engine.jar
///   # x86_64 release
///   - download.flutter.io/io/flutter/x86_64_release/1.0.0-$engine/x86_64_release-1.0.0-$engine.pom
///   - download.flutter.io/io/flutter/x86_64_release/1.0.0-$engine/x86_64_release-1.0.0-$engine.jar
/// ```
/// {@endtemplate}
@JsonSerializable(
  anyMap: true,
  disallowUnrecognizedKeys: true,
  createToJson: false,
)
class ArtifactsManifest {
  /// {@macro engine_mapping}
  const ArtifactsManifest({
    required this.flutterEngineRevision,
    required this.storageBucket,
    required this.artifactOverrides,
  });

  /// Creates an instance of [ArtifactsManifest] from the provided [json] map.
  factory ArtifactsManifest.fromJson(Map<dynamic, dynamic> json) =>
      _$ArtifactsManifestFromJson(json);

  /// The flutter engine revision that this engine mapping is based on.
  final String flutterEngineRevision;

  /// The storage bucket that contains the shorebird artifacts.
  final String storageBucket;

  /// The list of shorebird artifacts that should be overridden.
  final Set<String> artifactOverrides;
}
