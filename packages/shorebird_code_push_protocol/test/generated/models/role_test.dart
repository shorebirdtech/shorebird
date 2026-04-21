// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('Role', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = Role.values.first;
      final parsed = Role.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(Role.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => Role.maybeFromJson('__invalid_enum_value__'),
        throwsFormatException,
      );
    });

    test('toString matches toJson for every value', () {
      for (final value in Role.values) {
        expect(value.toString(), equals(value.toJson()));
      }
    });

    test('fromJson round-trips every value', () {
      for (final value in Role.values) {
        expect(Role.fromJson(value.toJson()), equals(value));
      }
    });
  });
}
