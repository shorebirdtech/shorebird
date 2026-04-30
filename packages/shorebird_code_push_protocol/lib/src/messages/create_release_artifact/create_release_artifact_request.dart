// Some OpenAPI specs flatten inline schemas into class names long
// enough that `dart format` can't keep imports and call sites under
// 80 cols as bare identifiers.
import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/release_platform.dart';

/// {@template create_release_artifact_request}
/// Metadata for a new release artifact. POST to
/// /apps/{appId}/releases/{releaseId}/artifacts and use the
/// returned signed upload URL to upload the artifact bytes
/// separately.
/// {@endtemplate}
@immutable
class CreateReleaseArtifactRequest {
  /// {@macro create_release_artifact_request}
  const CreateReleaseArtifactRequest({
    required this.arch,
    required this.platform,
    required this.hash,
    required this.filename,
    required this.size,
    this.canSideload,
    this.podfileLockHash,
  });

  /// Converts a `Map<String, dynamic>` to a [CreateReleaseArtifactRequest].
  factory CreateReleaseArtifactRequest.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'CreateReleaseArtifactRequest',
      json,
      () => CreateReleaseArtifactRequest(
        arch: json['arch'] as String,
        platform: ReleasePlatform.fromJson(json['platform'] as String),
        hash: json['hash'] as String,
        filename: json['filename'] as String,
        canSideload: json['can_sideload'] as bool?,
        size: json['size'] as int,
        podfileLockHash: json['podfile_lock_hash'] as String?,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static CreateReleaseArtifactRequest? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return CreateReleaseArtifactRequest.fromJson(json);
  }

  /// The arch of the artifact.
  final String arch;

  /// A platform to which a Shorebird release can be deployed.
  final ReleasePlatform platform;

  /// The hash of the artifact.
  final String hash;

  /// The name of the file.
  final String filename;

  /// Whether the artifact can installed and run on a device/emulator as-is.
  final bool? canSideload;

  /// The size of the artifact in bytes.
  final int size;

  /// The hash of the Podfile.lock file used to create this artifact (iOS
  /// only).
  final String? podfileLockHash;

  /// Converts a [CreateReleaseArtifactRequest] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'arch': arch,
      'platform': platform.toJson(),
      'hash': hash,
      'filename': filename,
      'can_sideload': canSideload,
      'size': size,
      'podfile_lock_hash': podfileLockHash,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    arch,
    platform,
    hash,
    filename,
    canSideload,
    size,
    podfileLockHash,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CreateReleaseArtifactRequest &&
        arch == other.arch &&
        platform == other.platform &&
        hash == other.hash &&
        filename == other.filename &&
        canSideload == other.canSideload &&
        size == other.size &&
        podfileLockHash == other.podfileLockHash;
  }
}
