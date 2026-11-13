import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/run_artifact_upload.dart';

/// {@template create_build_run_response}
/// The response body for POST /apps/{appId}/runs.
/// {@endtemplate}
@immutable
class CreateBuildRunResponse {
  /// {@macro create_build_run_response}
  const CreateBuildRunResponse({
    required this.id,
    this.artifactUploads,
  });

  /// Converts a `Map<String, dynamic>` to a [CreateBuildRunResponse].
  factory CreateBuildRunResponse.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'CreateBuildRunResponse',
      json,
      () => CreateBuildRunResponse(
        id: json['id'] as int,
        artifactUploads: (json['artifact_uploads'] as List?)
            ?.map<RunArtifactUpload>(
              (e) => RunArtifactUpload.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static CreateBuildRunResponse? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return CreateBuildRunResponse.fromJson(json);
  }

  /// The id of the recorded run.
  final int id;

  /// An upload for each declared file the server accepted, in no
  /// particular order. Absent when it accepted none.
  final List<RunArtifactUpload>? artifactUploads;

  /// Converts a [CreateBuildRunResponse] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'artifact_uploads': ?artifactUploads?.map((e) => e.toJson()).toList(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    listHash(artifactUploads),
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CreateBuildRunResponse &&
        id == other.id &&
        listsEqual(artifactUploads, other.artifactUploads);
  }
}
