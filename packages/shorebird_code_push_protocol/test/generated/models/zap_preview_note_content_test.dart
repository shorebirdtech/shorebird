// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('ZapPreviewNoteContent', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = ZapPreviewNoteContent();
      final parsed = ZapPreviewNoteContent.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(ZapPreviewNoteContent.maybeFromJson(null), isNull);
    });
  });
}
