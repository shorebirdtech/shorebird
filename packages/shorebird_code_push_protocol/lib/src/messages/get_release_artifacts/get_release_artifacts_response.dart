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
    this.nextCursor,
    this.totalCount,
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
        nextCursor: json['next_cursor'] as String?,
        totalCount: json['total_count'] as int?,
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

  /// The opaque cursor of the next page; send it back as `cursor`
  /// to get that page.
  /// Present only when the request was paginated (sent `per_page`,
  /// `cursor` or `page`) and another page follows. Absent on the last
  /// page and on unpaginated responses.
  final String? nextCursor;

  /// How many items the whole list holds. Present only when the
  /// request was paginated.
  final int? totalCount;

  /// Converts a [GetReleaseArtifactsResponse] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'artifacts': artifacts.map((e) => e.toJson()).toList(),
      'next_cursor': ?nextCursor,
      'total_count': ?totalCount,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    listHash(artifacts),
    nextCursor,
    totalCount,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GetReleaseArtifactsResponse &&
        listsEqual(artifacts, other.artifacts) &&
        nextCursor == other.nextCursor &&
        totalCount == other.totalCount;
  }
}
