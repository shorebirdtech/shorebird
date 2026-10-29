// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('SetEnterpriseMemberRoleRequest', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = SetEnterpriseMemberRoleRequest(
        role: EnterpriseRole.owner,
      );
      final parsed = SetEnterpriseMemberRoleRequest.maybeFromJson(
        instance.toJson(),
      )!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(SetEnterpriseMemberRoleRequest.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => SetEnterpriseMemberRoleRequest.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
