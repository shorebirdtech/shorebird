// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('EnterpriseRole', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = EnterpriseRole.owner;
      final parsed = EnterpriseRole.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(EnterpriseRole.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => EnterpriseRole.maybeFromJson('__invalid_enum_value__'),
        throwsFormatException,
      );
    });

    test('toString matches toJson for every value', () {
      for (final value in EnterpriseRole.values) {
        expect(value.toString(), equals(value.toJson()));
      }
    });

    test('fromJson round-trips every value', () {
      for (final value in EnterpriseRole.values) {
        expect(EnterpriseRole.fromJson(value.toJson()), equals(value));
      }
    });
  });
}
