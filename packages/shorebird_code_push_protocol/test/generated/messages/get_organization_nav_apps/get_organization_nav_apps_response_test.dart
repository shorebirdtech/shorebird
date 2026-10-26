// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('GetOrganizationNavAppsResponse', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = GetOrganizationNavAppsResponse(
        apps: <NavApp>[
          NavApp(appId: 'example', displayName: 'example', iconUrl: 'example'),
        ],
      );
      final parsed = GetOrganizationNavAppsResponse.maybeFromJson(
        instance.toJson(),
      )!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(GetOrganizationNavAppsResponse.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => GetOrganizationNavAppsResponse.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
