import 'package:json_annotation/json_annotation.dart';

part 'create_release_response.g.dart';

/// {@template create_release_response}
/// The response body for POST /api/v1/apps/<appId>/releases
/// {@endtemplate}
@JsonSerializable()
class CreateReleaseResponse {
  /// {@macro create_release_response}
  const CreateReleaseResponse({
    required this.id,
    required this.appId,
    required this.version,
    required this.flutterRevision,
    required this.displayName,
  });

  /// Converts a Map<String, dynamic> to a [CreateReleaseResponse]
  factory CreateReleaseResponse.fromJson(Map<String, dynamic> json) =>
      _$CreateReleaseResponseFromJson(json);

  /// Converts a [CreateReleaseResponse] to a Map<String, dynamic>
  Map<String, dynamic> toJson() => _$CreateReleaseResponseToJson(this);

  /// The ID of the release;
  final int id;

  /// The ID of the app.
  final String appId;

  /// The version of the release.
  final String version;

  /// The Flutter revision used to create the release.
  final String flutterRevision;

  /// The display name for the release
  final String? displayName;
}
