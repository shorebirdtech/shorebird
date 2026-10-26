// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('ZapPreviewNoteOrientation', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = ZapPreviewNoteOrientation.portrait;
      final parsed = ZapPreviewNoteOrientation.maybeFromJson(
        instance.toJson(),
      );
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(ZapPreviewNoteOrientation.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => ZapPreviewNoteOrientation.maybeFromJson('__invalid_enum_value__'),
        throwsFormatException,
      );
    });

    test('toString matches toJson for every value', () {
      for (final value in ZapPreviewNoteOrientation.values) {
        expect(value.toString(), equals(value.toJson()));
      }
    });

    test('fromJson round-trips every value', () {
      for (final value in ZapPreviewNoteOrientation.values) {
        expect(
          ZapPreviewNoteOrientation.fromJson(value.toJson()),
          equals(value),
        );
      }
    });
  });
}
