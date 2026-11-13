import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/run_artifact_kind.dart';
import 'package:shorebird_code_push_protocol/src/models/run_artifact_shared_by.dart';

/// {@template run_artifact_upload}
/// Where to upload a file the server accepted from a run.
/// {@endtemplate}
@immutable
class RunArtifactUpload {
  /// {@macro run_artifact_upload}
  const RunArtifactUpload({
    required this.id,
    required this.kind,
    required this.sharedBy,
    required this.uploadUrl,
  });

  /// Converts a `Map<String, dynamic>` to a [RunArtifactUpload].
  factory RunArtifactUpload.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'RunArtifactUpload',
      json,
      () => RunArtifactUpload(
        id: json['id'] as int,
        kind: RunArtifactKind.fromJson(json['kind'] as String),
        sharedBy: RunArtifactSharedBy.fromJson(json['shared_by'] as String),
        uploadUrl: Uri.parse(json['upload_url'] as String),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static RunArtifactUpload? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return RunArtifactUpload.fromJson(json);
  }

  /// The artifact's id.
  final int id;

  /// What a file a run shared is. Each kind has its own rule for when
  /// the customer has agreed to share it.
  final RunArtifactKind kind;

  /// Why a run shared a file with Shorebird.
  final RunArtifactSharedBy sharedBy;

  /// A GCS resumable upload session for the file, held to its
  /// declared `size_bytes`.
  final Uri uploadUrl;

  /// Converts a [RunArtifactUpload] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'kind': kind.toJson(),
      'shared_by': sharedBy.toJson(),
      'upload_url': uploadUrl.toString(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    kind,
    sharedBy,
    uploadUrl,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RunArtifactUpload &&
        id == other.id &&
        kind == other.kind &&
        sharedBy == other.sharedBy &&
        uploadUrl == other.uploadUrl;
  }
}
