import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/artifact_upload_method.dart';

/// {@template create_zap_preview_note_response}
/// The response body for POST /zap/previews/{previewId}/notes.
/// {@endtemplate}
@immutable
class CreateZapPreviewNoteResponse {
  /// {@macro create_zap_preview_note_response}
  const CreateZapPreviewNoteResponse({
    required this.note,
    required this.uploadUrl,
    required this.uploadMethod,
  });

  /// Converts a `Map<String, dynamic>` to a [CreateZapPreviewNoteResponse].
  factory CreateZapPreviewNoteResponse.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'CreateZapPreviewNoteResponse',
      json,
      () => CreateZapPreviewNoteResponse(
        note: json['note'] as String,
        uploadUrl: checkedKey(json, 'uploadUrl') as String?,
        uploadMethod: ArtifactUploadMethod.maybeFromJson(
          checkedKey(json, 'uploadMethod') as String?,
        ),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static CreateZapPreviewNoteResponse? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return CreateZapPreviewNoteResponse.fromJson(json);
  }

  /// The ID of the reserved note, which publishing takes.
  final String note;

  /// A Google Cloud Storage resumable upload session URI to upload the
  /// screenshot to, or null when no screenshot was declared.
  final String? uploadUrl;

  /// How a client should upload an artifact's bytes to storage.
  final ArtifactUploadMethod? uploadMethod;

  /// Converts a [CreateZapPreviewNoteResponse] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'note': note,
      'uploadUrl': uploadUrl,
      'uploadMethod': uploadMethod?.toJson(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    note,
    uploadUrl,
    uploadMethod,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CreateZapPreviewNoteResponse &&
        note == other.note &&
        uploadUrl == other.uploadUrl &&
        uploadMethod == other.uploadMethod;
  }
}
