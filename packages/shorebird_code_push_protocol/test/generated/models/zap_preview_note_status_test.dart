// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('ZapPreviewNoteStatus', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = ZapPreviewNoteStatus.open;
      final parsed = ZapPreviewNoteStatus.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(ZapPreviewNoteStatus.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => ZapPreviewNoteStatus.maybeFromJson('__invalid_enum_value__'),
        throwsFormatException,
      );
    });

    test('toString matches toJson for every value', () {
      for (final value in ZapPreviewNoteStatus.values) {
        expect(value.toString(), equals(value.toJson()));
      }
    });

    test('fromJson round-trips every value', () {
      for (final value in ZapPreviewNoteStatus.values) {
        expect(ZapPreviewNoteStatus.fromJson(value.toJson()), equals(value));
      }
    });
  });
}
