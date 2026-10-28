// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('GetServiceAccountTrustRulesResponse', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = GetServiceAccountTrustRulesResponse(
        trustRules: <ServiceAccountTrustRule>[
          ServiceAccountTrustRule(
            id: 0,
            provider: TrustRuleProvider.github,
            createdAt: DateTime.utc(2024),
            createdByUserId: 0,
            lastUsedAt: DateTime.utc(2024),
            github: const GithubTrustRule(
              repositoryOwner: 'example',
              repositoryOwnerId: 0,
              repositoryName: 'example',
              workflowPath: 'example',
              environment: 'example',
              refPattern: 'example',
            ),
          ),
        ],
      );
      final parsed = GetServiceAccountTrustRulesResponse.maybeFromJson(
        instance.toJson(),
      )!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(GetServiceAccountTrustRulesResponse.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => GetServiceAccountTrustRulesResponse.maybeFromJson(
          <String, dynamic>{},
        ),
        throwsFormatException,
      );
    });
  });
}
