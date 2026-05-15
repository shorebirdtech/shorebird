import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template release_analysis}
/// Analyzer-extracted metadata for a release artifact on a single
/// platform.
/// {@endtemplate}
@immutable
class ReleaseAnalysis {
  /// {@macro release_analysis}
  const ReleaseAnalysis({
    required this.displayName,
    required this.packageName,
    required this.minSdkVersion,
    required this.targetSdkVersion,
    required this.architectures,
  });

  /// Converts a `Map<String, dynamic>` to a [ReleaseAnalysis].
  factory ReleaseAnalysis.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'ReleaseAnalysis',
      json,
      () => ReleaseAnalysis(
        displayName: json['display_name'] as String,
        packageName: json['package_name'] as String,
        minSdkVersion: json['min_sdk_version'] as String,
        targetSdkVersion: json['target_sdk_version'] as String,
        architectures: (json['architectures'] as List).cast<String>(),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static ReleaseAnalysis? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return ReleaseAnalysis.fromJson(json);
  }

  /// The user-visible application name extracted from the artifact
  /// (e.g. AndroidManifest `application:label`). May differ from
  /// the user-curated `App.display_name`.
  final String displayName;

  /// The application package name (e.g. `com.example.app`).
  final String packageName;

  /// The minimum SDK level required to install the artifact
  /// (Android API level for android, iOS deployment target for ios).
  final String minSdkVersion;

  /// The SDK level the artifact targets (Android targetSdk for
  /// android, iOS SDK for ios).
  final String targetSdkVersion;

  /// CPU architectures present in the artifact
  /// (e.g. `["arm64-v8a", "armeabi-v7a"]`).
  final List<String> architectures;

  /// Converts a [ReleaseAnalysis] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'display_name': displayName,
      'package_name': packageName,
      'min_sdk_version': minSdkVersion,
      'target_sdk_version': targetSdkVersion,
      'architectures': architectures,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    displayName,
    packageName,
    minSdkVersion,
    targetSdkVersion,
    listHash(architectures),
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ReleaseAnalysis &&
        displayName == other.displayName &&
        packageName == other.packageName &&
        minSdkVersion == other.minSdkVersion &&
        targetSdkVersion == other.targetSdkVersion &&
        listsEqual(architectures, other.architectures);
  }
}
