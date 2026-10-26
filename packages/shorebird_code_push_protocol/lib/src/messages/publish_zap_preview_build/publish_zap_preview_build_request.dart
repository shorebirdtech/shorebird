import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template publish_zap_preview_build_request}
/// The request body for POST
/// /zap/previews/{previewId}/builds/{buildId}/publish. The body is
/// optional; an absent or unparseable body is treated as an empty one.
/// {@endtemplate}
@immutable
class PublishZapPreviewBuildRequest {
  /// {@macro publish_zap_preview_build_request}
  const PublishZapPreviewBuildRequest({
    this.name,
  });

  /// Converts a `Map<String, dynamic>` to a [PublishZapPreviewBuildRequest].
  factory PublishZapPreviewBuildRequest.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'PublishZapPreviewBuildRequest',
      json,
      () => PublishZapPreviewBuildRequest(
        name: json['name'] as String?,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static PublishZapPreviewBuildRequest? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return PublishZapPreviewBuildRequest.fromJson(json);
  }

  /// A new display name for the preview, trimmed, at most 64
  /// characters. Absent, blank or not
  /// a string, the preview keeps its name.
  final String? name;

  /// Converts a [PublishZapPreviewBuildRequest] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'name': ?name,
    };
  }

  @override
  int get hashCode => name.hashCode;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PublishZapPreviewBuildRequest && name == other.name;
  }
}
