// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('GetEnterpriseServiceAccountsSort', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = GetEnterpriseServiceAccountsSort.account;
      final parsed = GetEnterpriseServiceAccountsSort.maybeFromJson(
        instance.toJson(),
      );
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(GetEnterpriseServiceAccountsSort.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => GetEnterpriseServiceAccountsSort.maybeFromJson(
          '__invalid_enum_value__',
        ),
        throwsFormatException,
      );
    });

    test('toString matches toJson for every value', () {
      for (final value in GetEnterpriseServiceAccountsSort.values) {
        expect(value.toString(), equals(value.toJson()));
      }
    });

    test('fromJson round-trips every value', () {
      for (final value in GetEnterpriseServiceAccountsSort.values) {
        expect(
          GetEnterpriseServiceAccountsSort.fromJson(value.toJson()),
          equals(value),
        );
      }
    });
  });
}
