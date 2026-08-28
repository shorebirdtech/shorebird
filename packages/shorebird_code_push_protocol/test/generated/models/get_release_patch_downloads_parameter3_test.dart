// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('GetReleasePatchDownloadsParameter3', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = GetReleasePatchDownloadsParameter3.values.first;
      final parsed = GetReleasePatchDownloadsParameter3.maybeFromJson(
        instance.toJson(),
      );
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(GetReleasePatchDownloadsParameter3.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => GetReleasePatchDownloadsParameter3.maybeFromJson(
          '__invalid_enum_value__',
        ),
        throwsFormatException,
      );
    });

    test('toString matches toJson for every value', () {
      for (final value in GetReleasePatchDownloadsParameter3.values) {
        expect(value.toString(), equals(value.toJson()));
      }
    });

    test('fromJson round-trips every value', () {
      for (final value in GetReleasePatchDownloadsParameter3.values) {
        expect(
          GetReleasePatchDownloadsParameter3.fromJson(value.toJson()),
          equals(value),
        );
      }
    });
  });
}
