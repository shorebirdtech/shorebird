// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('ZapPreviewNote', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = ZapPreviewNote(
        id: 'example',
        text: 'example',
        route: 'example',
        orientation: ZapPreviewNoteOrientation.portrait,
        strokes: const <dynamic>[<String, dynamic>{}],
        buildId: 'example',
        status: ZapPreviewNoteStatus.open,
        createdAt: DateTime.utc(2024),
        updatedAt: DateTime.utc(2024),
      );
      final parsed = ZapPreviewNote.maybeFromJson(instance.toJson());
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(ZapPreviewNote.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => ZapPreviewNote.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
