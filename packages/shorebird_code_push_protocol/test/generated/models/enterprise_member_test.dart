// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('EnterpriseMember', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = EnterpriseMember(
        userId: 0,
        email: 'example',
        displayName: 'example',
        kind: 'example',
        teams: const <EnterpriseTeamAccess>[
          EnterpriseTeamAccess(teamId: 0, role: Role.owner),
        ],
        appGrants: const <EnterpriseAppGrant>[
          EnterpriseAppGrant(appId: 'example', role: Role.owner),
        ],
        signInMethod: SignInMethod.google,
        signedInAt: DateTime.utc(2024),
        lastActiveAt: DateTime.utc(2024),
        role: EnterpriseRole.owner,
        removedAt: DateTime.utc(2024),
        removedByEmail: 'example',
      );
      final parsed = EnterpriseMember.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(EnterpriseMember.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => EnterpriseMember.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
