// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('CreateZapPreviewNoteRequest', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = CreateZapPreviewNoteRequest();
      final parsed = CreateZapPreviewNoteRequest.maybeFromJson(
        instance.toJson(),
      );
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(CreateZapPreviewNoteRequest.maybeFromJson(null), isNull);
    });
  });
}
