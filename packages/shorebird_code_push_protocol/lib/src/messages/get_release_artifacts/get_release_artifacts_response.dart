// Some OpenAPI specs flatten inline schemas into class names long
// enough that `dart format` can't keep imports and call sites under
// 80 cols as bare identifiers.
import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/release_artifact.dart';

/// {@template get_release_artifacts_response}
/// The response body for GET /apps/{appId}/releases/{releaseId}/artifacts.
/// {@endtemplate}
@immutable
class GetReleaseArtifactsResponse {
  /// {@macro get_release_artifacts_response}
  const GetReleaseArtifactsResponse({
    required this.artifacts,
  });

  /// Converts a `Map<String, dynamic>` to a [GetReleaseArtifactsResponse].
  factory GetReleaseArtifactsResponse.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'GetReleaseArtifactsResponse',
      json,
      () => GetReleaseArtifactsResponse(
        artifacts: (json['artifacts'] as List)
            .map<ReleaseArtifact>(
              (e) => ReleaseArtifact.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static GetReleaseArtifactsResponse? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return GetReleaseArtifactsResponse.fromJson(json);
  }

  /// The artifacts for the release.
  final List<ReleaseArtifact> artifacts;

  /// Converts a [GetReleaseArtifactsResponse] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'artifacts': artifacts.map((e) => e.toJson()).toList(),
    };
  }

  @override
  int get hashCode => listHash(artifacts).hashCode;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GetReleaseArtifactsResponse &&
        listsEqual(artifacts, other.artifacts);
  }
}
