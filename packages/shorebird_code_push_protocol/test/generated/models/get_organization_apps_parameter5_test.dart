// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('GetOrganizationAppsParameter5', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = GetOrganizationAppsParameter5.updated;
      final parsed = GetOrganizationAppsParameter5.maybeFromJson(
        instance.toJson(),
      )!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(GetOrganizationAppsParameter5.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => GetOrganizationAppsParameter5.maybeFromJson(
          '__invalid_enum_value__',
        ),
        throwsFormatException,
      );
    });

    test('toString matches toJson for every value', () {
      for (final value in GetOrganizationAppsParameter5.values) {
        expect(value.toString(), equals(value.toJson()));
      }
    });

    test('fromJson round-trips every value', () {
      for (final value in GetOrganizationAppsParameter5.values) {
        expect(
          GetOrganizationAppsParameter5.fromJson(value.toJson()),
          equals(value),
        );
      }
    });
  });
}
