// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('RemoveEnterpriseMember200Response', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = RemoveEnterpriseMember200Response(
        organizations: <EnterpriseRemovedAccessOrganizationsInner>[
          EnterpriseRemovedAccessOrganizationsInner(
            organizationId: 0,
            organizationName: 'example',
            role: Role.owner,
          ),
        ],
        appGrants: <EnterpriseRemovedAccessAppGrantsInner>[
          EnterpriseRemovedAccessAppGrantsInner(
            appId: 'example',
            organizationId: 0,
            role: Role.owner,
          ),
        ],
        invitationsRevoked: 0,
        sessionsRevoked: 0,
        apiKeysRevoked: 0,
      );
      final parsed = RemoveEnterpriseMember200Response.maybeFromJson(
        instance.toJson(),
      )!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(RemoveEnterpriseMember200Response.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => RemoveEnterpriseMember200Response.maybeFromJson(
          <String, dynamic>{},
        ),
        throwsFormatException,
      );
    });
  });
}
