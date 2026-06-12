// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('GetUniqueUsersParameter3', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = GetUniqueUsersParameter3.values.first;
      final parsed = GetUniqueUsersParameter3.maybeFromJson(instance.toJson());
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(GetUniqueUsersParameter3.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => GetUniqueUsersParameter3.maybeFromJson('__invalid_enum_value__'),
        throwsFormatException,
      );
    });

    test('toString matches toJson for every value', () {
      for (final value in GetUniqueUsersParameter3.values) {
        expect(value.toString(), equals(value.toJson()));
      }
    });

    test('fromJson round-trips every value', () {
      for (final value in GetUniqueUsersParameter3.values) {
        expect(
          GetUniqueUsersParameter3.fromJson(value.toJson()),
          equals(value),
        );
      }
    });
  });
}
