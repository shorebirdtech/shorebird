// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('SetEnterpriseOrganizationMemberRoleRequest', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = SetEnterpriseOrganizationMemberRoleRequest(
        role: Role.owner,
      );
      final parsed = SetEnterpriseOrganizationMemberRoleRequest.maybeFromJson(
        instance.toJson(),
      )!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(
        SetEnterpriseOrganizationMemberRoleRequest.maybeFromJson(null),
        isNull,
      );
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => SetEnterpriseOrganizationMemberRoleRequest.maybeFromJson(
          <String, dynamic>{},
        ),
        throwsFormatException,
      );
    });
  });
}
