// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('AddEnterpriseOrganizationMemberRequest', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = AddEnterpriseOrganizationMemberRequest(
        userId: 0,
        role: Role.owner,
      );
      final parsed = AddEnterpriseOrganizationMemberRequest.maybeFromJson(
        instance.toJson(),
      );
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(
        AddEnterpriseOrganizationMemberRequest.maybeFromJson(null),
        isNull,
      );
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => AddEnterpriseOrganizationMemberRequest.maybeFromJson(
          <String, dynamic>{},
        ),
        throwsFormatException,
      );
    });
  });
}
