import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('ReleaseExtensions', () {
    Release release({
      List<ReleasePlatformDetails>? platforms,
      Map<ReleasePlatform, ReleaseStatus>? platformStatuses,
    }) => Release(
      id: 1,
      appId: 'app-id',
      version: '1.0.0',
      flutterRevision: 'abc',
      platforms: platforms,
      // The fallback for servers that predate `platforms` is what's tested.
      // ignore: deprecated_member_use_from_same_package
      platformStatuses: platformStatuses,
      createdAt: DateTime.utc(2023),
      updatedAt: DateTime.utc(2023),
    );

    test('reads platforms when the server sends them', () {
      final subject = release(
        platforms: const [
          ReleasePlatformDetails(
            platform: ReleasePlatform.android,
            status: ReleaseStatus.active,
            signingMode: 'managed',
          ),
        ],
        platformStatuses: const {ReleasePlatform.ios: ReleaseStatus.draft},
      );
      expect(subject.platformDetails, hasLength(1));
      expect(
        subject.statusFor(ReleasePlatform.android),
        equals(ReleaseStatus.active),
      );
      expect(subject.statusFor(ReleasePlatform.ios), isNull);
    });

    test('falls back to the statuses a server that predates platforms '
        'sends', () {
      final subject = release(
        platformStatuses: const {ReleasePlatform.ios: ReleaseStatus.draft},
      );
      expect(subject.platformDetails, const [
        ReleasePlatformDetails(
          platform: ReleasePlatform.ios,
          status: ReleaseStatus.draft,
        ),
      ]);
      expect(subject.statusFor(ReleasePlatform.ios), ReleaseStatus.draft);
    });

    test('is empty when the server sends neither', () {
      expect(release().platformDetails, isEmpty);
      expect(release().statusFor(ReleasePlatform.android), isNull);
    });
  });
}
