import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

part 'update_patch_request.g.dart';

/// {@template update_patch_request}
/// Request body for PATCH
/// `api/v1/apps/:appId/releases/:releaseId/patch/:patchId` requests.
/// {@endtemplate}
@JsonSerializable()
class UpdatePatchRequest {
  /// {@macro update_patch_request}
  const UpdatePatchRequest({this.notes});

  /// Converts a `Map<String, dynamic>` to a [UpdatePatchRequest].
  factory UpdatePatchRequest.fromJson(Json json) =>
      _$UpdatePatchRequestFromJson(json);

  /// Converts a [UpdatePatchRequest] to a `Map<String, dynamic>`.
  Json toJson() => _$UpdatePatchRequestToJson(this);

  /// Notes about the patch. This is a free-form field that can be used to
  /// store additional information about the release. If null, the notes will
  /// not be updated.
  final String? notes;
}
