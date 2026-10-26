// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('GetOrganizationAppsParameter6', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = GetOrganizationAppsParameter6.asc;
      final parsed = GetOrganizationAppsParameter6.maybeFromJson(
        instance.toJson(),
      );
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(GetOrganizationAppsParameter6.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => GetOrganizationAppsParameter6.maybeFromJson(
          '__invalid_enum_value__',
        ),
        throwsFormatException,
      );
    });

    test('toString matches toJson for every value', () {
      for (final value in GetOrganizationAppsParameter6.values) {
        expect(value.toString(), equals(value.toJson()));
      }
    });

    test('fromJson round-trips every value', () {
      for (final value in GetOrganizationAppsParameter6.values) {
        expect(
          GetOrganizationAppsParameter6.fromJson(value.toJson()),
          equals(value),
        );
      }
    });
  });
}
