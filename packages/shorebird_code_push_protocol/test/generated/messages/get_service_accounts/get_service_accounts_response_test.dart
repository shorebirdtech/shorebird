// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('GetServiceAccountsResponse', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = GetServiceAccountsResponse(
        serviceAccounts: <ServiceAccount>[
          ServiceAccount(
            id: 0,
            organizationId: 0,
            name: 'example',
            label: 'example',
            role: ServiceAccountRole.viewer,
            createdAt: DateTime.utc(2024),
            createdByUserId: 0,
            createdByEmail: 'example',
            lastAuthAt: DateTime.utc(2024),
          ),
        ],
      );
      final parsed = GetServiceAccountsResponse.maybeFromJson(
        instance.toJson(),
      )!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(GetServiceAccountsResponse.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => GetServiceAccountsResponse.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
