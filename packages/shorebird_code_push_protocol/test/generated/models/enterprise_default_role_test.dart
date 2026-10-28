// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('EnterpriseDefaultRole', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = EnterpriseDefaultRole.viewer;
      final parsed = EnterpriseDefaultRole.maybeFromJson(instance.toJson());
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(EnterpriseDefaultRole.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => EnterpriseDefaultRole.maybeFromJson('__invalid_enum_value__'),
        throwsFormatException,
      );
    });

    test('toString matches toJson for every value', () {
      for (final value in EnterpriseDefaultRole.values) {
        expect(value.toString(), equals(value.toJson()));
      }
    });

    test('fromJson round-trips every value', () {
      for (final value in EnterpriseDefaultRole.values) {
        expect(EnterpriseDefaultRole.fromJson(value.toJson()), equals(value));
      }
    });
  });
}
