import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/src/models/create_patch_metadata.dart';

part 'create_patch_request.g.dart';

/// {@template create_patch_request}
/// The request body for POST /api/v1/patches
/// {@endtemplate}
@JsonSerializable()
class CreatePatchRequest {
  /// {@macro create_patch_request}
  const CreatePatchRequest({
    required this.releaseId,
    required this.wasForced,
    required this.metadata,
  });

  /// Converts a Map<String, dynamic> to a [CreatePatchRequest]
  factory CreatePatchRequest.fromJson(Map<String, dynamic> json) =>
      _$CreatePatchRequestFromJson(json);

  /// Converts a [CreatePatchRequest] to a Map<String, dynamic>
  Map<String, dynamic> toJson() => _$CreatePatchRequestToJson(this);

  /// The ID of the release.
  final int releaseId;

  /// Whether the user used the --force flag when authoring this patch.
  final bool? wasForced;

  /// Additional information about the creation of the patch.
  final CreatePatchMetadata metadata;
}
