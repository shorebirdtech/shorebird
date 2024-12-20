import 'package:json_annotation/json_annotation.dart';

part 'create_release_request.g.dart';

/// {@template create_release_request}
/// The request body for POST /api/v1/apps/:appId/releases
/// {@endtemplate}
@JsonSerializable()
class CreateReleaseRequest {
  /// {@macro create_release_request}
  const CreateReleaseRequest({
    required this.version,
    required this.flutterRevision,
    required this.flutterVersion,
    this.displayName,
  });

  /// Converts a `Map<String, dynamic>` to a [CreateReleaseRequest]
  factory CreateReleaseRequest.fromJson(Map<String, dynamic> json) =>
      _$CreateReleaseRequestFromJson(json);

  /// Converts a [CreateReleaseRequest] to a `Map<String, dynamic>`
  Map<String, dynamic> toJson() => _$CreateReleaseRequestToJson(this);

  /// The release version.
  final String version;

  /// The Flutter revision used to create the release.
  final String flutterRevision;

  /// The Flutter version used to create the release.
  ///
  /// This field is optional because it was newly added and
  /// older releases do not have this information.
  final String? flutterVersion;

  /// The display name for the release.
  final String? displayName;
}
