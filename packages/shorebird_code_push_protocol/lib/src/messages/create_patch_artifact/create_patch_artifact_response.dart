import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

part 'create_patch_artifact_response.g.dart';

/// {@template create_patch_artifact_response}
/// The response body for POST /api/v1/patches/<id>/artifacts
/// {@endtemplate}
@JsonSerializable()
class CreatePatchArtifactResponse {
  /// {@macro create_artifact_response}
  const CreatePatchArtifactResponse({
    required this.arch,
    required this.platform,
    required this.hash,
    required this.size,
    required this.url,
  });

  /// Converts a Map<String, dynamic> to a [CreatePatchArtifactResponse]
  factory CreatePatchArtifactResponse.fromJson(Map<String, dynamic> json) =>
      _$CreatePatchArtifactResponseFromJson(json);

  /// Converts a [CreatePatchArtifactResponse] to a Map<String, dynamic>.
  Json toJson() => _$CreatePatchArtifactResponseToJson(this);

  /// The arch of the artifact.
  final String arch;

  /// The platform of the artifact.
  final String platform;

  /// The hash of the artifact.
  final String hash;

  /// The size of the artifact in bytes.
  @JsonKey(fromJson: _parseStringToInt, toJson: _parseIntToString)
  final int size;

  /// The upload URL for the artifact.
  final String url;

  static int _parseStringToInt(dynamic value) => int.parse(value as String);

  static String _parseIntToString(dynamic value) => value.toString();
}
