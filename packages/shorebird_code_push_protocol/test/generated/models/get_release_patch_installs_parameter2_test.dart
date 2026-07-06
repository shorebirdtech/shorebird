// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('GetReleasePatchInstallsParameter2', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = GetReleasePatchInstallsParameter2.values.first;
      final parsed = GetReleasePatchInstallsParameter2.maybeFromJson(
        instance.toJson(),
      )!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(GetReleasePatchInstallsParameter2.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => GetReleasePatchInstallsParameter2.maybeFromJson(
          '__invalid_enum_value__',
        ),
        throwsFormatException,
      );
    });

    test('toString matches toJson for every value', () {
      for (final value in GetReleasePatchInstallsParameter2.values) {
        expect(value.toString(), equals(value.toJson()));
      }
    });

    test('fromJson round-trips every value', () {
      for (final value in GetReleasePatchInstallsParameter2.values) {
        expect(
          GetReleasePatchInstallsParameter2.fromJson(value.toJson()),
          equals(value),
        );
      }
    });
  });
}
