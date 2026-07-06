import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/artifact_upload_method.dart';
import 'package:shorebird_code_push_protocol/src/models/release_platform.dart';

/// {@template create_release_artifact_response}
/// The response body for registering a release artifact.
/// {@endtemplate}
@immutable
class CreateReleaseArtifactResponse {
  /// {@macro create_release_artifact_response}
  const CreateReleaseArtifactResponse({
    required this.id,
    required this.releaseId,
    required this.arch,
    required this.platform,
    required this.hash,
    required this.size,
    required this.url,
    this.uploadMethod,
  });

  /// Converts a `Map<String, dynamic>` to a [CreateReleaseArtifactResponse].
  factory CreateReleaseArtifactResponse.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'CreateReleaseArtifactResponse',
      json,
      () => CreateReleaseArtifactResponse(
        id: json['id'] as int,
        releaseId: json['release_id'] as int,
        arch: json['arch'] as String,
        platform: ReleasePlatform.fromJson(json['platform'] as String),
        hash: json['hash'] as String,
        size: json['size'] as int,
        url: json['url'] as String,
        uploadMethod: ArtifactUploadMethod.maybeFromJson(
          json['upload_method'] as String?,
        ),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static CreateReleaseArtifactResponse? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return CreateReleaseArtifactResponse.fromJson(json);
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

  /// The upload URL for the artifact.
  final String url;

  /// How a client should upload an artifact's bytes to storage, returned
  /// by the create-artifact endpoints so the client knows how to use the
  /// `url` it was handed. `multipart` is the legacy single
  /// `multipart/form-data` POST of the file to a signed URL. `resumable`
  /// is a resumable upload: PUT the bytes (chunked, with `Content-Range`)
  /// to a server-initiated GCS resumable session URI given in `url` — the
  /// session is size-bound at initiation, so GCS rejects an oversized
  /// upload.
  final ArtifactUploadMethod? uploadMethod;

  /// Converts a [CreateReleaseArtifactResponse] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'release_id': releaseId,
      'arch': arch,
      'platform': platform.toJson(),
      'hash': hash,
      'size': size,
      'url': url,
      'upload_method': uploadMethod?.toJson(),
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
    uploadMethod,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CreateReleaseArtifactResponse &&
        id == other.id &&
        releaseId == other.releaseId &&
        arch == other.arch &&
        platform == other.platform &&
        hash == other.hash &&
        size == other.size &&
        url == other.url &&
        uploadMethod == other.uploadMethod;
  }
}
