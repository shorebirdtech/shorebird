// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('SetEnterpriseMemberRole200Response', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = SetEnterpriseMemberRole200Response(
        userId: 0,
        role: EnterpriseRole.owner,
      );
      final parsed = SetEnterpriseMemberRole200Response.maybeFromJson(
        instance.toJson(),
      );
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(SetEnterpriseMemberRole200Response.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => SetEnterpriseMemberRole200Response.maybeFromJson(
          <String, dynamic>{},
        ),
        throwsFormatException,
      );
    });
  });
}
