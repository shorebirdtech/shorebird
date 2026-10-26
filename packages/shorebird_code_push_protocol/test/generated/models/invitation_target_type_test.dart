// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('InvitationTargetType', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = InvitationTargetType.organization;
      final parsed = InvitationTargetType.maybeFromJson(instance.toJson());
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(InvitationTargetType.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => InvitationTargetType.maybeFromJson('__invalid_enum_value__'),
        throwsFormatException,
      );
    });

    test('toString matches toJson for every value', () {
      for (final value in InvitationTargetType.values) {
        expect(value.toString(), equals(value.toJson()));
      }
    });

    test('fromJson round-trips every value', () {
      for (final value in InvitationTargetType.values) {
        expect(InvitationTargetType.fromJson(value.toJson()), equals(value));
      }
    });
  });
}
