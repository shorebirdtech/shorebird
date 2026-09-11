import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template create_patch_request}
/// The request body for POST /apps/{appId}/patches.
/// {@endtemplate}
@immutable
class CreatePatchRequest {
  /// {@macro create_patch_request}
  const CreatePatchRequest({
    required this.releaseId,
    required this.metadata,
  });

  /// Converts a `Map<String, dynamic>` to a [CreatePatchRequest].
  factory CreatePatchRequest.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'CreatePatchRequest',
      json,
      () => CreatePatchRequest(
        releaseId: json['release_id'] as int,
        metadata: (json['metadata'] as Map<String, dynamic>).map(
          MapEntry.new,
        ),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static CreatePatchRequest? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return CreatePatchRequest.fromJson(json);
  }

  /// The ID of the release.
  final int releaseId;

  /// Additional information about the command that was run to
  /// create the patch and the environment it was run in.
  final Map<String, dynamic> metadata;

  /// Converts a [CreatePatchRequest] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'release_id': releaseId,
      'metadata': metadata,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    releaseId,
    mapHash(metadata),
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CreatePatchRequest &&
        releaseId == other.releaseId &&
        mapsEqual(metadata, other.metadata);
  }
}
