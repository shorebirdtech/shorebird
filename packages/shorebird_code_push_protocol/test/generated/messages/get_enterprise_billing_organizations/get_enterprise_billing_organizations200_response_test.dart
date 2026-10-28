// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('GetEnterpriseBillingOrganizations200Response', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = GetEnterpriseBillingOrganizations200Response(
        totalCount: 0,
        organizations: <EnterpriseBillingOrganization>[
          EnterpriseBillingOrganization(
            id: 0,
            name: 'example',
            appCount: 0,
            patchInstalls: 0,
          ),
        ],
      );
      final parsed = GetEnterpriseBillingOrganizations200Response.maybeFromJson(
        instance.toJson(),
      );
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(
        GetEnterpriseBillingOrganizations200Response.maybeFromJson(null),
        isNull,
      );
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => GetEnterpriseBillingOrganizations200Response.maybeFromJson(
          <String, dynamic>{},
        ),
        throwsFormatException,
      );
    });
  });
}
