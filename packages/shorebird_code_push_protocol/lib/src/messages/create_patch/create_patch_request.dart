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
    this.clientPatchId,
    this.gitSha,
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
        clientPatchId: json['client_patch_id'] as String?,
        gitSha: json['git_sha'] as String?,
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

  /// Optional client-supplied correlation key used to make patch
  /// creation idempotent across invocations. When two requests on
  /// the same release supply the same value, the server returns the
  /// existing patch instead of creating a new one — letting
  /// cross-platform builds share one patch number. Most commonly a
  /// git SHA, but any stable token works. At most 255 characters.
  final String? clientPatchId;

  /// The commit SHA the patch was built from, recorded for provenance
  /// and display. Sent whenever the patch is cut inside a git checkout,
  /// independent of `client_patch_id` — so the originating commit is
  /// retained even when grouping was keyed on an explicit correlation
  /// key. Suffixed with `-dirty` when the working tree had uncommitted
  /// changes, so the recorded provenance never claims a commit that
  /// doesn't match the shipped code. Null when the patch was created
  /// outside a git checkout. At most 255 characters.
  final String? gitSha;

  /// Converts a [CreatePatchRequest] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'release_id': releaseId,
      'metadata': metadata,
      'client_patch_id': clientPatchId,
      'git_sha': gitSha,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    releaseId,
    mapHash(metadata),
    clientPatchId,
    gitSha,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CreatePatchRequest &&
        releaseId == other.releaseId &&
        mapsEqual(metadata, other.metadata) &&
        clientPatchId == other.clientPatchId &&
        gitSha == other.gitSha;
  }
}
