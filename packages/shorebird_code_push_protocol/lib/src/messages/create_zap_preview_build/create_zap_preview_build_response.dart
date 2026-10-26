import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/artifact_upload_method.dart';

/// {@template create_zap_preview_build_response}
/// The response body for POST /zap/previews/{previewId}/builds.
/// {@endtemplate}
@immutable
class CreateZapPreviewBuildResponse {
  /// {@macro create_zap_preview_build_response}
  const CreateZapPreviewBuildResponse({
    required this.build,
    required this.uploadUrl,
    required this.uploadMethod,
  });

  /// Converts a `Map<String, dynamic>` to a [CreateZapPreviewBuildResponse].
  factory CreateZapPreviewBuildResponse.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'CreateZapPreviewBuildResponse',
      json,
      () => CreateZapPreviewBuildResponse(
        build: json['build'] as String,
        uploadUrl: json['uploadUrl'] as String,
        uploadMethod: ArtifactUploadMethod.fromJson(
          json['uploadMethod'] as String,
        ),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static CreateZapPreviewBuildResponse? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return CreateZapPreviewBuildResponse.fromJson(json);
  }

  /// The ID of the reserved build, which publishing takes.
  final String build;

  /// A Google Cloud Storage resumable upload session URI to upload the
  /// payload (`application/zip`) to.
  final String uploadUrl;

  /// How a client should upload an artifact's bytes to storage.
  final ArtifactUploadMethod uploadMethod;

  /// Converts a [CreateZapPreviewBuildResponse] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'build': build,
      'uploadUrl': uploadUrl,
      'uploadMethod': uploadMethod.toJson(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    build,
    uploadUrl,
    uploadMethod,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CreateZapPreviewBuildResponse &&
        build == other.build &&
        uploadUrl == other.uploadUrl &&
        uploadMethod == other.uploadMethod;
  }
}
