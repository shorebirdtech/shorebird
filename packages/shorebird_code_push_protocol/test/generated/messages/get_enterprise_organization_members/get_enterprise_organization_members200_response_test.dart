// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('GetEnterpriseOrganizationMembers200Response', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = GetEnterpriseOrganizationMembers200Response(
        totalCount: 0,
        users: <OrganizationUser>[
          OrganizationUser(
            user: PublicUser(id: 0, email: 'user@example.com'),
            role: Role.owner,
          ),
        ],
      );
      final parsed = GetEnterpriseOrganizationMembers200Response.maybeFromJson(
        instance.toJson(),
      )!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(
        GetEnterpriseOrganizationMembers200Response.maybeFromJson(null),
        isNull,
      );
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => GetEnterpriseOrganizationMembers200Response.maybeFromJson(
          <String, dynamic>{},
        ),
        throwsFormatException,
      );
    });
  });
}
