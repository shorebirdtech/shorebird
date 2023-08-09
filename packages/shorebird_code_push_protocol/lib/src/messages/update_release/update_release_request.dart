import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

part 'update_release_request.g.dart';

/// {@template update_release_request}
/// Request body for PUT `api/v1/release/:id` requests.
/// {@endtemplate}
@JsonSerializable()
class UpdateReleaseRequest {
  /// {@macro update_release_request}
  const UpdateReleaseRequest({
    required this.status,
    required this.platform,
  });

  /// Converts a Map<String, dynamic> to a [UpdateReleaseRequest].
  factory UpdateReleaseRequest.fromJson(Json json) =>
      _$UpdateReleaseRequestFromJson(json);

  /// Converts a [UpdateReleaseRequest] to a Map<String, dynamic>.
  Json toJson() => _$UpdateReleaseRequestToJson(this);

  /// The desired status of the release.
  final ReleaseStatus status;

  /// The platform of the release.
  final ReleasePlatform platform;
}
