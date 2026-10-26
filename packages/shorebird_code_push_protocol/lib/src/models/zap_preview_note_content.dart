import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/zap_preview_note_orientation.dart';
import 'package:shorebird_code_push_protocol/src/models/zap_preview_note_status.dart';

/// {@template zap_preview_note_content}
/// The fields of a note its author writes, all optional. A note with
/// none of them is still a note; the screenshot may be all it says.
/// Strings are trimmed, and an empty `text` or `route` is stored as
/// null. Each string field must be a string when present.
/// {@endtemplate}
@immutable
class ZapPreviewNoteContent {
  /// {@macro zap_preview_note_content}
  const ZapPreviewNoteContent({
    this.text,
    this.route,
    this.orientation,
    this.strokes,
    this.buildId,
    this.status,
  });

  /// Converts a `Map<String, dynamic>` to a [ZapPreviewNoteContent].
  factory ZapPreviewNoteContent.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'ZapPreviewNoteContent',
      json,
      () => ZapPreviewNoteContent(
        text: json['text'] as String?,
        route: json['route'] as String?,
        orientation: ZapPreviewNoteOrientation.maybeFromJson(
          json['orientation'] as String?,
        ),
        strokes: (json['strokes'] as List?)?.cast<dynamic>(),
        buildId: json['buildId'] as String?,
        status: ZapPreviewNoteStatus.maybeFromJson(json['status'] as String?),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static ZapPreviewNoteContent? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return ZapPreviewNoteContent.fromJson(json);
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

  /// Converts a [ZapPreviewNoteContent] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'route': route,
      'orientation': orientation?.toJson(),
      'strokes': strokes,
      'buildId': buildId,
      'status': status?.toJson(),
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
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ZapPreviewNoteContent &&
        text == other.text &&
        route == other.route &&
        orientation == other.orientation &&
        listsEqual(strokes, other.strokes) &&
        buildId == other.buildId &&
        status == other.status;
  }
}
