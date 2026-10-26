import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/zap_preview_note_orientation.dart';
import 'package:shorebird_code_push_protocol/src/models/zap_preview_note_status.dart';

/// {@template zap_preview_note_list_entry}
/// A published note as it appears in a list, with its screenshot URL.
/// {@endtemplate}
@immutable
class ZapPreviewNoteListEntry {
  /// {@macro zap_preview_note_list_entry}
  const ZapPreviewNoteListEntry({
    required this.id,
    required this.text,
    required this.route,
    required this.orientation,
    required this.strokes,
    required this.buildId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.screenshotUrl,
  });

  /// Converts a `Map<String, dynamic>` to a [ZapPreviewNoteListEntry].
  factory ZapPreviewNoteListEntry.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'ZapPreviewNoteListEntry',
      json,
      () => ZapPreviewNoteListEntry(
        id: json['id'] as String,
        text: checkedKey(json, 'text') as String?,
        route: checkedKey(json, 'route') as String?,
        orientation: ZapPreviewNoteOrientation.maybeFromJson(
          checkedKey(json, 'orientation') as String?,
        ),
        strokes: (checkedKey(json, 'strokes') as List?)?.cast<dynamic>(),
        buildId: checkedKey(json, 'buildId') as String?,
        status: ZapPreviewNoteStatus.fromJson(json['status'] as String),
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        screenshotUrl: checkedKey(json, 'screenshotUrl') as String?,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static ZapPreviewNoteListEntry? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return ZapPreviewNoteListEntry.fromJson(json);
  }

  /// The ID of the note.
  final String id;

  /// What the person wrote.
  final String? text;

  /// Where in the app they were, as the app names it.
  final String? route;

  /// Which way the device was held when a note was left.
  final ZapPreviewNoteOrientation? orientation;

  /// Markup drawn over the screenshot, opaque to the server.
  final List<dynamic>? strokes;

  /// The ID of the build the note was left against.
  final String? buildId;

  /// Whether a note is still open.
  final ZapPreviewNoteStatus status;

  /// When the note was published.
  final DateTime createdAt;

  /// When the note was last changed; equal to `createdAt` until it is.
  final DateTime updatedAt;

  /// A signed URL to download the note's screenshot from, valid for
  /// 15 minutes, or null when the note has none.
  final String? screenshotUrl;

  /// Converts a [ZapPreviewNoteListEntry] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'route': route,
      'orientation': orientation?.toJson(),
      'strokes': strokes,
      'buildId': buildId,
      'status': status.toJson(),
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      'screenshotUrl': screenshotUrl,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    text,
    route,
    orientation,
    listHash(strokes),
    buildId,
    status,
    createdAt,
    updatedAt,
    screenshotUrl,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ZapPreviewNoteListEntry &&
        id == other.id &&
        text == other.text &&
        route == other.route &&
        orientation == other.orientation &&
        listsEqual(strokes, other.strokes) &&
        buildId == other.buildId &&
        status == other.status &&
        createdAt == other.createdAt &&
        updatedAt == other.updatedAt &&
        screenshotUrl == other.screenshotUrl;
  }
}
