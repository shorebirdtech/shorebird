import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/release_platform.dart';

/// {@template release_artifact}
/// An artifact contains metadata about the contents of a specific
/// release for a specific platform and architecture.
/// {@endtemplate}
@immutable
class ReleaseArtifact {
  /// {@macro release_artifact}
  const ReleaseArtifact({
    required this.id,
    required this.releaseId,
    required this.arch,
    required this.platform,
    required this.hash,
    required this.size,
    required this.url,
    required this.canSideload,
    this.podfileLockHash,
  });

  /// Converts a `Map<String, dynamic>` to a [ReleaseArtifact].
  factory ReleaseArtifact.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'ReleaseArtifact',
      json,
      () => ReleaseArtifact(
        id: json['id'] as int,
        releaseId: json['release_id'] as int,
        arch: json['arch'] as String,
        platform: ReleasePlatform.fromJson(json['platform'] as String),
        hash: json['hash'] as String,
        size: json['size'] as int,
        url: json['url'] as String,
        podfileLockHash: json['podfile_lock_hash'] as String?,
        canSideload: json['can_sideload'] as bool,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static ReleaseArtifact? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return ReleaseArtifact.fromJson(json);
  }

  /// The ID of the artifact.
  final int id;

  /// The ID of the release.
  final int releaseId;

  /// The arch of the artifact.
  final String arch;

  /// A platform to which a Shorebird release can be deployed.
  final ReleasePlatform platform;

  /// The hash of the artifact.
  final String hash;

  /// The size of the artifact in bytes.
  final int size;

  /// The url of the artifact.
  final String url;

  /// sha256 of the Podfile.lock used to create the artifact (iOS only).
  final String? podfileLockHash;

  /// Whether the artifact can be sideloaded onto a device.
  final bool canSideload;

  /// Converts a [ReleaseArtifact] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'release_id': releaseId,
      'arch': arch,
      'platform': platform.toJson(),
      'hash': hash,
      'size': size,
      'url': url,
      'podfile_lock_hash': podfileLockHash,
      'can_sideload': canSideload,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    releaseId,
    arch,
    platform,
    hash,
    size,
    url,
    podfileLockHash,
    canSideload,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ReleaseArtifact &&
        id == other.id &&
        releaseId == other.releaseId &&
        arch == other.arch &&
        platform == other.platform &&
        hash == other.hash &&
        size == other.size &&
        url == other.url &&
        podfileLockHash == other.podfileLockHash &&
        canSideload == other.canSideload;
  }
}
