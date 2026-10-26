import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/zap_preview_note_orientation.dart';
import 'package:shorebird_code_push_protocol/src/models/zap_preview_note_status.dart';

/// {@template zap_preview_note}
/// A published note.
/// {@endtemplate}
@immutable
class ZapPreviewNote {
  /// {@macro zap_preview_note}
  const ZapPreviewNote({
    required this.id,
    required this.text,
    required this.route,
    required this.orientation,
    required this.strokes,
    required this.buildId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Converts a `Map<String, dynamic>` to a [ZapPreviewNote].
  factory ZapPreviewNote.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'ZapPreviewNote',
      json,
      () => ZapPreviewNote(
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
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static ZapPreviewNote? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return ZapPreviewNote.fromJson(json);
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

  /// Converts a [ZapPreviewNote] to a `Map<String, dynamic>`.
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
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ZapPreviewNote &&
        id == other.id &&
        text == other.text &&
        route == other.route &&
        orientation == other.orientation &&
        listsEqual(strokes, other.strokes) &&
        buildId == other.buildId &&
        status == other.status &&
        createdAt == other.createdAt &&
        updatedAt == other.updatedAt;
  }
}
