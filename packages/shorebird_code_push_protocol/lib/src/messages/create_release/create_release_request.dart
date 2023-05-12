import 'package:json_annotation/json_annotation.dart';

part 'create_release_request.g.dart';

/// {@template create_release_request}
/// The request body for POST /api/v1/releases
/// {@endtemplate}
@JsonSerializable()
class CreateReleaseRequest {
  /// {@macro create_release_request}
  const CreateReleaseRequest({
    required this.appId,
    required this.version,
    this.flutterRevision,
    this.displayName,
  });

  /// Converts a Map<String, dynamic> to a [CreateReleaseRequest]
  factory CreateReleaseRequest.fromJson(Map<String, dynamic> json) =>
      _$CreateReleaseRequestFromJson(json);

  /// Converts a [CreateReleaseRequest] to a Map<String, dynamic>
  Map<String, dynamic> toJson() => _$CreateReleaseRequestToJson(this);

  /// The ID of the app.
  final String appId;

  /// The release version.
  final String version;

  /// The Flutter revision used to create the release.
  /// This is nullable for backward compatibility.
  final String? flutterRevision;

  /// The display name for the release.
  final String? displayName;
}
