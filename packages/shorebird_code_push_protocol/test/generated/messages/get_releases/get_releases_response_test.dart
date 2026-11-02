// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('GetReleasesResponse', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = GetReleasesResponse(
        releases: <Release>[
          Release(
            id: 0,
            appId: 'example',
            version: 'example',
            flutterRevision: 'example',
            platforms: const {
              ReleasePlatform.android: ReleasePlatformDetails(
                status: ReleaseStatus.draft,
              ),
            },
            createdAt: DateTime.utc(2024),
            updatedAt: DateTime.utc(2024),
          ),
        ],
      );
      final parsed = GetReleasesResponse.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(GetReleasesResponse.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => GetReleasesResponse.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
