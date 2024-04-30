import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

part 'create_patch_artifact_request.g.dart';

/// {@template create_patch_artifact_request}
/// The request body for POST /api/v1/patches/<id>/artifacts
/// {@endtemplate}
@JsonSerializable()
class CreatePatchArtifactRequest {
  /// {@macro create_artifact_request}
  const CreatePatchArtifactRequest({
    required this.arch,
    required this.platform,
    required this.hash,
    required this.size,
    this.hashSignature,
  });

  /// Converts a Map<String, dynamic> to a [CreatePatchArtifactRequest]
  factory CreatePatchArtifactRequest.fromJson(Map<String, dynamic> json) =>
      _$CreatePatchArtifactRequestFromJson(json);

  /// Converts a [CreatePatchArtifactRequest] to a Map<String, dynamic>.
  Json toJson() => _$CreatePatchArtifactRequestToJson(this);

  /// The arch of the artifact.
  final String arch;

  /// The platform of the artifact.
  final ReleasePlatform platform;

  /// The hash of the artifact.
  final String hash;

  /// The signature of the [hash].
  ///
  /// Patch code signing is an opt in feature, introduced later in the life of
  /// the product, so when this field is null, the patch does not uses code
  /// signing.
  final String? hashSignature;

  /// The size of the artifact in bytes.
  @JsonKey(fromJson: _parseStringToInt, toJson: _parseIntToString)
  final int size;

  static int _parseStringToInt(dynamic value) => int.parse(value as String);

  static String _parseIntToString(dynamic value) => value.toString();
}
