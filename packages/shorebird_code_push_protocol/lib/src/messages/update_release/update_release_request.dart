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
    this.status,
    this.platform,
    this.metadata,
    this.notes,
  });

  /// Converts a `Map<String, dynamic>` to a [UpdateReleaseRequest].
  factory UpdateReleaseRequest.fromJson(Json json) =>
      _$UpdateReleaseRequestFromJson(json);

  /// Converts a [UpdateReleaseRequest] to a `Map<String, dynamic>`.
  Json toJson() => _$UpdateReleaseRequestToJson(this);

  /// The desired status of the release. If provided, [platform] must also be
  /// provided If null, the status will not be updated.
  final ReleaseStatus? status;

  /// The platform of the release. If provided, [status] must also be provided.
  final ReleasePlatform? platform;

  /// Additional information about the command that was run to update the
  /// release and the environment in which it was run.
  final Json? metadata;

  /// Notes about the release. This is a free-form field that can be used to
  /// store additional information about the release. If null, the notes will
  /// not be updated.
  final String? notes;
}
