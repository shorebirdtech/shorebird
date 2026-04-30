// Some OpenAPI specs flatten inline schemas into class names long
// enough that `dart format` can't keep imports and call sites under
// 80 cols as bare identifiers.
// Spec descriptions copy prose verbatim into dartdoc, where `[x]`
// inside a sentence (placeholder text, ALL_CAPS tokens, license
// templates) is parsed as a symbol reference even when no such
// symbol exists. Suppress file-locally so the lint stays live
// elsewhere; spec authors do not always escape brackets.
import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/release_platform.dart';

/// {@template create_patch_artifact_request}
/// Metadata for a new patch artifact. POST to
/// /apps/{appId}/patches/{patchId}/artifacts and use the returned
/// signed upload URL to upload the artifact bytes separately.
/// {@endtemplate}
@immutable
class CreatePatchArtifactRequest {
  /// {@macro create_patch_artifact_request}
  const CreatePatchArtifactRequest({
    required this.arch,
    required this.platform,
    required this.hash,
    required this.size,
    this.hashSignature,
    this.podfileLockHash,
  });

  /// Converts a `Map<String, dynamic>` to a [CreatePatchArtifactRequest].
  factory CreatePatchArtifactRequest.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'CreatePatchArtifactRequest',
      json,
      () => CreatePatchArtifactRequest(
        arch: json['arch'] as String,
        platform: ReleasePlatform.fromJson(json['platform'] as String),
        hash: json['hash'] as String,
        hashSignature: json['hash_signature'] as String?,
        podfileLockHash: json['podfile_lock_hash'] as String?,
        size: json['size'] as int,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static CreatePatchArtifactRequest? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return CreatePatchArtifactRequest.fromJson(json);
  }

  /// The arch of the artifact.
  final String arch;

  /// A platform to which a Shorebird release can be deployed.
  final ReleasePlatform platform;

  /// The hash of the artifact.
  final String hash;

  /// The signature of the [hash].  Patch code signing is an opt in feature,
  /// introduced later in the life of the product, so when this field is null,
  /// the patch does not uses code signing.
  final String? hashSignature;

  /// The sha256 hash of the Podfile.lock file, if a Podfile.lock file was
  /// involved in the creation of the patch (iOS only).
  final String? podfileLockHash;

  /// The size of the artifact in bytes.
  final int size;

  /// Converts a [CreatePatchArtifactRequest] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'arch': arch,
      'platform': platform.toJson(),
      'hash': hash,
      'hash_signature': hashSignature,
      'podfile_lock_hash': podfileLockHash,
      'size': size,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    arch,
    platform,
    hash,
    hashSignature,
    podfileLockHash,
    size,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CreatePatchArtifactRequest &&
        arch == other.arch &&
        platform == other.platform &&
        hash == other.hash &&
        hashSignature == other.hashSignature &&
        podfileLockHash == other.podfileLockHash &&
        size == other.size;
  }
}
