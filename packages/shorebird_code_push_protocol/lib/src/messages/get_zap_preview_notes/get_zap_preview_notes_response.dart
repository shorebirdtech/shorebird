import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/zap_preview_note_list_entry.dart';

/// {@template get_zap_preview_notes_response}
/// The response body for GET /zap/previews/{previewId}/notes.
/// {@endtemplate}
@immutable
class GetZapPreviewNotesResponse {
  /// {@macro get_zap_preview_notes_response}
  const GetZapPreviewNotesResponse({
    required this.notes,
    this.nextCursor,
  });

  /// Converts a `Map<String, dynamic>` to a [GetZapPreviewNotesResponse].
  factory GetZapPreviewNotesResponse.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'GetZapPreviewNotesResponse',
      json,
      () => GetZapPreviewNotesResponse(
        notes: (json['notes'] as List)
            .map<ZapPreviewNoteListEntry>(
              (e) =>
                  ZapPreviewNoteListEntry.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
        nextCursor: json['next_cursor'] as String?,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static GetZapPreviewNotesResponse? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return GetZapPreviewNotesResponse.fromJson(json);
  }

  /// The notes on this page, newest first.
  final List<ZapPreviewNoteListEntry> notes;

  /// The opaque cursor of the next page; send it back as `cursor`
  /// to get that page. Absent on the last page.
  final String? nextCursor;

  /// Converts a [GetZapPreviewNotesResponse] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'notes': notes.map((e) => e.toJson()).toList(),
      'next_cursor': ?nextCursor,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    listHash(notes),
    nextCursor,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GetZapPreviewNotesResponse &&
        listsEqual(notes, other.notes) &&
        nextCursor == other.nextCursor;
  }
}
