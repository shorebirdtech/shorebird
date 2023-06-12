import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

part 'get_release_artifacts_response.g.dart';

/// {@template get_release_artifacts_response}
/// The response body for GET /api/v1/release/:release/artifacts
/// {@endtemplate}
@JsonSerializable()
class GetReleaseArtifactsResponse {
  /// {@macro get_release_artifacts_response}
  const GetReleaseArtifactsResponse({required this.artifacts});

  /// Converts a Map<String, dynamic> to a [GetReleaseArtifactsResponse].
  factory GetReleaseArtifactsResponse.fromJson(Map<String, dynamic> json) =>
      _$GetReleaseArtifactsResponseFromJson(json);

  /// Converts a [GetReleaseArtifactsResponse] to a Map<String, dynamic>.
  Json toJson() => _$GetReleaseArtifactsResponseToJson(this);

  /// The artifacts for the release.
  final List<ReleaseArtifact> artifacts;
}
