import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('ReleaseExtensions', () {
    Release release({
      Map<ReleasePlatform, ReleasePlatformDetails>? platforms,
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
        platforms: const {
          ReleasePlatform.android: ReleasePlatformDetails(
            status: ReleaseStatus.active,
            signingMode: 'managed',
          ),
          ReleasePlatform.macos: ReleasePlatformDetails(
            status: ReleaseStatus.draft,
          ),
        },
        platformStatuses: const {ReleasePlatform.ios: ReleaseStatus.draft},
      );
      expect(subject.platformDetails, hasLength(2));
      expect(subject.hasPlatform(ReleasePlatform.android), isTrue);
      expect(subject.hasPlatform(ReleasePlatform.ios), isFalse);
      expect(subject.statusFor(ReleasePlatform.macos), ReleaseStatus.draft);
      expect(subject.isActiveOn(ReleasePlatform.android), isTrue);
      expect(subject.isActiveOn(ReleasePlatform.macos), isFalse);
      expect(subject.activePlatforms, [ReleasePlatform.android]);
    });

    test('falls back to the statuses a server that predates platforms '
        'sends', () {
      final subject = release(
        platformStatuses: const {ReleasePlatform.ios: ReleaseStatus.draft},
      );
      expect(subject.platformDetails, const {
        ReleasePlatform.ios: ReleasePlatformDetails(
          status: ReleaseStatus.draft,
        ),
      });
      expect(subject.hasPlatform(ReleasePlatform.ios), isTrue);
      expect(subject.statusFor(ReleasePlatform.ios), ReleaseStatus.draft);
    });

    test('is empty when the server sends neither', () {
      final subject = release();
      expect(subject.platformDetails, isEmpty);
      expect(subject.hasPlatform(ReleasePlatform.android), isFalse);
      expect(subject.statusFor(ReleasePlatform.android), isNull);
      expect(subject.isActiveOn(ReleasePlatform.android), isFalse);
      expect(subject.activePlatforms, isEmpty);
    });
  });
}
