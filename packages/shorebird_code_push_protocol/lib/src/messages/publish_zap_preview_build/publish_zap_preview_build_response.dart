import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template publish_zap_preview_build_response}
/// The response body for POST
/// /zap/previews/{previewId}/builds/{buildId}/publish.
/// {@endtemplate}
@immutable
class PublishZapPreviewBuildResponse {
  /// {@macro publish_zap_preview_build_response}
  const PublishZapPreviewBuildResponse({
    required this.preview,
    required this.build,
    required this.name,
    required this.bytes,
  });

  /// Converts a `Map<String, dynamic>` to a [PublishZapPreviewBuildResponse].
  factory PublishZapPreviewBuildResponse.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'PublishZapPreviewBuildResponse',
      json,
      () => PublishZapPreviewBuildResponse(
        preview: json['preview'] as String,
        build: json['build'] as String,
        name: json['name'] as String,
        bytes: json['bytes'] as int,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static PublishZapPreviewBuildResponse? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return PublishZapPreviewBuildResponse.fromJson(json);
  }

  /// The ID of the preview.
  final String preview;

  /// The ID of the published build.
  final String build;

  /// The preview's display name after the publish. On a retry of a
  /// publish that already happened, the preview's current name; a
  /// rename the retry asked for is not applied.
  final String name;

  /// The payload's size in bytes.
  final int bytes;

  /// Converts a [PublishZapPreviewBuildResponse] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'preview': preview,
      'build': build,
      'name': name,
      'bytes': bytes,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    preview,
    build,
    name,
    bytes,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PublishZapPreviewBuildResponse &&
        preview == other.preview &&
        build == other.build &&
        name == other.name &&
        bytes == other.bytes;
  }
}
