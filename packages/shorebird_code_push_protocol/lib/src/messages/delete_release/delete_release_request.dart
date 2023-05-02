import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

part 'delete_release_request.g.dart';

/// {@template delete_release_request}
/// The request body for POST /api/v1/users, which creates a new User.
///
/// Email is retrieved from the user's auth token.
/// {@endtemplate}
@JsonSerializable()
class DeleteReleaseRequest {
  /// {@macro delete_release_request}
  const DeleteReleaseRequest({
    required this.appId,
    required this.version,
  });

  /// Converts a JSON object to a [DeleteReleaseRequest].
  factory DeleteReleaseRequest.fromJson(Json json) =>
      _$DeleteReleaseRequestFromJson(json);

  /// Converts a [DeleteReleaseRequest] to a JSON object.
  Json toJson() => _$DeleteReleaseRequestToJson(this);

  /// The id of the app associated with the release to delete.
  final String appId;

  /// The version string of the release to delete.
  final String version;
}
