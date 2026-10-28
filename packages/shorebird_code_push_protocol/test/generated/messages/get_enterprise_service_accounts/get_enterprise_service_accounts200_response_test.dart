// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('GetEnterpriseServiceAccounts200Response', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = GetEnterpriseServiceAccounts200Response(
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
        serviceAccounts: <EnterpriseServiceAccount>[
          EnterpriseServiceAccount(
            userId: 0,
            name: 'example',
            teamId: 0,
            role: Role.owner,
            createdAt: DateTime.utc(2024),
            lastAuthAt: DateTime.utc(2024),
            createdByEmail: 'example',
          ),
        ],
      );
      final parsed = GetEnterpriseServiceAccounts200Response.maybeFromJson(
        instance.toJson(),
      );
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(
        GetEnterpriseServiceAccounts200Response.maybeFromJson(null),
        isNull,
      );
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => GetEnterpriseServiceAccounts200Response.maybeFromJson(
          <String, dynamic>{},
        ),
        throwsFormatException,
      );
    });
  });
}
