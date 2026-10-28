// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('GetEnterpriseMembers200Response', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = GetEnterpriseMembers200Response(
        totalCount: 0,
        teams: const <EnterpriseTeam>[
          EnterpriseTeam(
            id: 0,
            name: 'example',
            memberCount: 0,
            appCount: 0,
            defaultRole: EnterpriseDefaultRole.viewer,
            apps: <EnterpriseAppSummary>[
              EnterpriseAppSummary(id: 'example', displayName: 'example'),
            ],
          ),
        ],
        apps: const <EnterpriseAppSummary>[
          EnterpriseAppSummary(id: 'example', displayName: 'example'),
        ],
        members: <EnterpriseMember>[
          EnterpriseMember(
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
          ),
        ],
        memberCount: 0,
        removedCount: 0,
      );
      final parsed = GetEnterpriseMembers200Response.maybeFromJson(
        instance.toJson(),
      );
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(GetEnterpriseMembers200Response.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () =>
            GetEnterpriseMembers200Response.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
