// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('GetReleasePatchDownloadsGroupBy', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = GetReleasePatchDownloadsGroupBy.patch;
      final parsed = GetReleasePatchDownloadsGroupBy.maybeFromJson(
        instance.toJson(),
      );
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(GetReleasePatchDownloadsGroupBy.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => GetReleasePatchDownloadsGroupBy.maybeFromJson(
          '__invalid_enum_value__',
        ),
        throwsFormatException,
      );
    });

    test('toString matches toJson for every value', () {
      for (final value in GetReleasePatchDownloadsGroupBy.values) {
        expect(value.toString(), equals(value.toJson()));
      }
    });

    test('fromJson round-trips every value', () {
      for (final value in GetReleasePatchDownloadsGroupBy.values) {
        expect(
          GetReleasePatchDownloadsGroupBy.fromJson(value.toJson()),
          equals(value),
        );
      }
    });
  });
}
