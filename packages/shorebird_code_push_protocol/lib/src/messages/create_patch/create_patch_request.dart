import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/release_platform.dart';

/// {@template create_patch_request}
/// The request body for POST /apps/{appId}/patches.
/// {@endtemplate}
@immutable
class CreatePatchRequest {
  /// {@macro create_patch_request}
  const CreatePatchRequest({
    required this.releaseId,
    required this.metadata,
    this.platform,
    this.linkKey,
    this.gitSha,
    this.gitDirty,
  });

  /// Converts a `Map<String, dynamic>` to a [CreatePatchRequest].
  factory CreatePatchRequest.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'CreatePatchRequest',
      json,
      () => CreatePatchRequest(
        releaseId: json['release_id'] as int,
        metadata: json['metadata'] as Map<String, dynamic>,
        platform: ReleasePlatform.maybeFromJson(json['platform'] as String?),
        linkKey: json['link_key'] as String?,
        gitSha: json['git_sha'] as String?,
        gitDirty: json['git_dirty'] as bool?,
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

  /// The platform the patch is built for. Linking needs it; without
  /// it the server reads `metadata.release_platform`.
  /// Unstable: this may change shape until patch linking ships.
  final ReleasePlatform? platform;

  /// Links this platform's patch to patches for other platforms
  /// created with the same key on the release, so they share a
  /// number. Clients send one key for every platform built from one
  /// commit, usually its SHA. At most 255 characters; a blank key is
  /// refused.
  /// Unstable: this may change shape until patch linking ships.
  final String? linkKey;

  /// The commit the patch was built from, when it is built in a git
  /// checkout, as at most 64 hex characters. Recorded as provenance whether
  /// or not the patch is
  /// linked. Unstable: this may change shape until patch linking ships.
  final String? gitSha;

  /// Whether the git working tree had uncommitted changes when the
  /// patch was built. Sent with `git_sha`.
  /// Unstable: this may change shape until patch linking ships.
  final bool? gitDirty;

  /// Converts a [CreatePatchRequest] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'release_id': releaseId,
      'metadata': metadata,
      'platform': ?platform?.toJson(),
      'link_key': ?linkKey,
      'git_sha': ?gitSha,
      'git_dirty': ?gitDirty,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    releaseId,
    mapHash(metadata),
    platform,
    linkKey,
    gitSha,
    gitDirty,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CreatePatchRequest &&
        releaseId == other.releaseId &&
        mapsEqual(metadata, other.metadata) &&
        platform == other.platform &&
        linkKey == other.linkKey &&
        gitSha == other.gitSha &&
        gitDirty == other.gitDirty;
  }
}
