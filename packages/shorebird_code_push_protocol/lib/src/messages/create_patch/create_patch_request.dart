import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

part 'create_patch_request.g.dart';

/// {@template create_patch_request}
/// The request body for POST /api/v1/patches
/// {@endtemplate}
@JsonSerializable()
class CreatePatchRequest {
  /// {@macro create_patch_request}
  const CreatePatchRequest({
    required this.releaseId,
    required this.metadata,
  });

  /// Converts a Map<String, dynamic> to a [CreatePatchRequest]
  factory CreatePatchRequest.fromJson(Map<String, dynamic> json) =>
      _$CreatePatchRequestFromJson(json);

  /// Converts a [CreatePatchRequest] to a Map<String, dynamic>
  Map<String, dynamic> toJson() => _$CreatePatchRequestToJson(this);

  /// The ID of the release.
  final int releaseId;

  /// Additional information about the command that was run to create the patch
  /// and the environment in which it was run.
  final Json metadata;
}
