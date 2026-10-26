import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/zap_screenshot_content_type.dart';

/// {@template zap_screenshot_upload}
/// A screenshot a note will carry, declared before it is uploaded.
/// {@endtemplate}
@immutable
class ZapScreenshotUpload {
  /// {@macro zap_screenshot_upload}
  const ZapScreenshotUpload({
    required this.size,
    required this.contentType,
  });

  /// Converts a `Map<String, dynamic>` to a [ZapScreenshotUpload].
  factory ZapScreenshotUpload.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'ZapScreenshotUpload',
      json,
      () => ZapScreenshotUpload(
        size: json['size'] as int,
        contentType: ZapScreenshotContentType.fromJson(
          json['contentType'] as String,
        ),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static ZapScreenshotUpload? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return ZapScreenshotUpload.fromJson(json);
  }

  /// A positive integer: the image's size in bytes, at most 16 MiB
  /// (16777216).
  final int size;

  /// The content type of a note's screenshot.
  final ZapScreenshotContentType contentType;

  /// Converts a [ZapScreenshotUpload] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'size': size,
      'contentType': contentType.toJson(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    size,
    contentType,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ZapScreenshotUpload &&
        size == other.size &&
        contentType == other.contentType;
  }
}
