import 'package:json_annotation/json_annotation.dart';

part 'create_release_artifact_request.g.dart';

/// {@template create_release_artifact_request}
/// The request body for POST /api/v1/artifacts/:id/artifacts
/// {@endtemplate}
@JsonSerializable(createToJson: false)
class CreateReleaseArtifactRequest {
  /// {@macro create_release_artifact_request}
  const CreateReleaseArtifactRequest({
    required this.arch,
    required this.platform,
    required this.hash,
    required this.size,
  });

  /// Converts a Map<String, dynamic> to a [CreateReleaseArtifactRequest]
  factory CreateReleaseArtifactRequest.fromJson(Map<String, dynamic> json) =>
      _$CreateReleaseArtifactRequestFromJson(json);

  /// The arch of the artifact.
  final String arch;

  /// The platform of the artifact.
  final String platform;

  /// The hash of the artifact.
  final String hash;

  /// The size of the artifact in bytes.
  @JsonKey(fromJson: _parseStringToInt)
  final int size;

  static int _parseStringToInt(dynamic value) => int.parse(value as String);
}
