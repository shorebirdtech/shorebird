// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('GetAppsResponse', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = GetAppsResponse(
        apps: <AppMetadata>[
          AppMetadata(
            appId: 'example',
            displayName: 'example',
            createdAt: DateTime.utc(2024),
            updatedAt: DateTime.utc(2024),
          ),
        ],
      );
      final parsed = GetAppsResponse.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(GetAppsResponse.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => GetAppsResponse.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
