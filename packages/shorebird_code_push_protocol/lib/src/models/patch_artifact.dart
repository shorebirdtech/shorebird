// Some OpenAPI specs flatten inline schemas into class names long
// enough that `dart format` can't keep imports and call sites under
// 80 cols as bare identifiers.
import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/release_platform.dart';

/// {@template patch_artifact}
/// Metadata about the contents of a specific patch for a specific
/// platform and architecture.
/// {@endtemplate}
@immutable
class PatchArtifact {
  /// {@macro patch_artifact}
  const PatchArtifact({
    required this.id,
    required this.patchId,
    required this.arch,
    required this.platform,
    required this.hash,
    required this.size,
    required this.createdAt,
  });

  /// Converts a `Map<String, dynamic>` to a [PatchArtifact].
  factory PatchArtifact.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'PatchArtifact',
      json,
      () => PatchArtifact(
        id: json['id'] as int,
        patchId: json['patch_id'] as int,
        arch: json['arch'] as String,
        platform: ReleasePlatform.fromJson(json['platform'] as String),
        hash: json['hash'] as String,
        size: json['size'] as int,
        createdAt: DateTime.parse(json['created_at'] as String),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static PatchArtifact? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return PatchArtifact.fromJson(json);
  }

  /// The ID of the artifact.
  final int id;

  /// The ID of the patch.
  final int patchId;

  /// The arch of the artifact.
  final String arch;

  /// A platform to which a Shorebird release can be deployed.
  final ReleasePlatform platform;

  /// The hash of the artifact.
  final String hash;

  /// The size of the artifact in bytes.
  final int size;

  /// The date and time the artifact was created.
  final DateTime createdAt;

  /// Converts a [PatchArtifact] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'patch_id': patchId,
      'arch': arch,
      'platform': platform.toJson(),
      'hash': hash,
      'size': size,
      'created_at': createdAt.toIso8601String(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    patchId,
    arch,
    platform,
    hash,
    size,
    createdAt,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PatchArtifact &&
        id == other.id &&
        patchId == other.patchId &&
        arch == other.arch &&
        platform == other.platform &&
        hash == other.hash &&
        size == other.size &&
        createdAt == other.createdAt;
  }
}
