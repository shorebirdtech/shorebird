import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

part 'create_release_artifact_request.g.dart';

/// {@template create_release_artifact_request}
/// The request body for POST /api/v1/artifacts/:id/artifacts
///
/// Because this request is sent as a http.MultipartRequest, all fields
/// serialize to strings.
/// {@endtemplate}
@JsonSerializable()
class CreateReleaseArtifactRequest {
  /// {@macro create_release_artifact_request}
  const CreateReleaseArtifactRequest({
    required this.arch,
    required this.platform,
    required this.hash,
    required this.size,
    required this.canSideload,
  });

  /// Converts a Map<String, dynamic> to a [CreateReleaseArtifactRequest]
  factory CreateReleaseArtifactRequest.fromJson(Map<String, dynamic> json) =>
      _$CreateReleaseArtifactRequestFromJson(json);

  /// Converts a [CreateReleaseArtifactRequest] to a Map<String, dynamic>.
  Json toJson() => _$CreateReleaseArtifactRequestToJson(this);

  /// The arch of the artifact.
  final String arch;

  /// The platform of the artifact.
  final ReleasePlatform platform;

  /// The hash of the artifact.
  final String hash;

  /// Whether the artifact can installed and run on a device/emulator as-is.
  @JsonKey(fromJson: _parseStringToBool, toJson: _parseBoolToString)
  final bool? canSideload;

  /// The size of the artifact in bytes.
  @JsonKey(fromJson: _parseStringToInt, toJson: _parseIntToString)
  final int size;

  static int _parseStringToInt(dynamic value) => int.parse(value as String);

  static String _parseIntToString(dynamic value) => value.toString();

  static bool _parseStringToBool(dynamic value) => value == 'true';

  static String _parseBoolToString(dynamic value) => value.toString();
}
