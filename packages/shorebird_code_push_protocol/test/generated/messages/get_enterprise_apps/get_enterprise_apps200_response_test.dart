// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('GetEnterpriseApps200Response', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = GetEnterpriseApps200Response(
        totalCount: 0,
        apps: <EnterpriseApp>[
          EnterpriseApp(
            organizationId: 0,
            organizationName: 'example',
            appId: 'example',
            appDisplayName: 'example',
          ),
        ],
      );
      final parsed = GetEnterpriseApps200Response.maybeFromJson(
        instance.toJson(),
      );
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(GetEnterpriseApps200Response.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => GetEnterpriseApps200Response.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
