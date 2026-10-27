// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('GetUniqueUsersGroupBy', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = GetUniqueUsersGroupBy.platform;
      final parsed = GetUniqueUsersGroupBy.maybeFromJson(instance.toJson());
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(GetUniqueUsersGroupBy.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => GetUniqueUsersGroupBy.maybeFromJson('__invalid_enum_value__'),
        throwsFormatException,
      );
    });

    test('toString matches toJson for every value', () {
      for (final value in GetUniqueUsersGroupBy.values) {
        expect(value.toString(), equals(value.toJson()));
      }
    });

    test('fromJson round-trips every value', () {
      for (final value in GetUniqueUsersGroupBy.values) {
        expect(GetUniqueUsersGroupBy.fromJson(value.toJson()), equals(value));
      }
    });
  });
}
