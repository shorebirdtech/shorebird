import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/zap_preview_note_orientation.dart';
import 'package:shorebird_code_push_protocol/src/models/zap_preview_note_status.dart';
import 'package:shorebird_code_push_protocol/src/models/zap_screenshot_upload.dart';

/// {@template create_zap_preview_note_request}
/// The request body for POST /zap/previews/{previewId}/notes: the note's
/// content, validated but not stored, and the screenshot to upload, if
/// any.
/// {@endtemplate}
@immutable
class CreateZapPreviewNoteRequest {
  /// {@macro create_zap_preview_note_request}
  const CreateZapPreviewNoteRequest({
    this.text,
    this.route,
    this.orientation,
    this.strokes,
    this.buildId,
    this.status,
    this.screenshot,
  });

  /// Converts a `Map<String, dynamic>` to a [CreateZapPreviewNoteRequest].
  factory CreateZapPreviewNoteRequest.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'CreateZapPreviewNoteRequest',
      json,
      () => CreateZapPreviewNoteRequest(
        text: json['text'] as String?,
        route: json['route'] as String?,
        orientation: ZapPreviewNoteOrientation.maybeFromJson(
          json['orientation'] as String?,
        ),
        strokes: (json['strokes'] as List?)?.cast<dynamic>(),
        buildId: json['buildId'] as String?,
        status: ZapPreviewNoteStatus.maybeFromJson(json['status'] as String?),
        screenshot: ZapScreenshotUpload.maybeFromJson(
          json['screenshot'] as Map<String, dynamic>?,
        ),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static CreateZapPreviewNoteRequest? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return CreateZapPreviewNoteRequest.fromJson(json);
  }

  /// What the person wrote, at most 4096 characters.
  final String? text;

  /// Where in the app they were, as the app names it, at most 256
  /// characters.
  final String? route;

  /// Which way the device was held when a note was left.
  final ZapPreviewNoteOrientation? orientation;

  /// Markup drawn over the screenshot, opaque to the server. At most
  /// 256 KiB when encoded as JSON.
  final List<dynamic>? strokes;

  /// The ID of the build the note was left against.
  final String? buildId;

  /// Whether a note is still open.
  final ZapPreviewNoteStatus? status;

  /// A screenshot a note will carry, declared before it is uploaded.
  final ZapScreenshotUpload? screenshot;

  /// Converts a [CreateZapPreviewNoteRequest] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'route': route,
      'orientation': orientation?.toJson(),
      'strokes': strokes,
      'buildId': buildId,
      'status': status?.toJson(),
      'screenshot': ?screenshot?.toJson(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    text,
    route,
    orientation,
    listHash(strokes),
    buildId,
    status,
    screenshot,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CreateZapPreviewNoteRequest &&
        text == other.text &&
        route == other.route &&
        orientation == other.orientation &&
        listsEqual(strokes, other.strokes) &&
        buildId == other.buildId &&
        status == other.status &&
        screenshot == other.screenshot;
  }
}
