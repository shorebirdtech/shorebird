import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('ReleaseExtensions', () {
    Release release({
      Map<ReleasePlatform, ReleasePlatformDetails> platforms = const {},
    }) => Release(
      id: 1,
      appId: 'app-id',
      version: '1.0.0',
      flutterRevision: 'abc',
      platforms: platforms,
      createdAt: DateTime.utc(2023),
      updatedAt: DateTime.utc(2023),
    );

    test("reads each platform's status", () {
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
      );
      expect(subject.hasPlatform(ReleasePlatform.android), isTrue);
      expect(subject.hasPlatform(ReleasePlatform.ios), isFalse);
      expect(subject.statusFor(ReleasePlatform.macos), ReleaseStatus.draft);
      expect(subject.statusFor(ReleasePlatform.ios), isNull);
      expect(subject.isActiveOn(ReleasePlatform.android), isTrue);
      expect(subject.isActiveOn(ReleasePlatform.macos), isFalse);
      expect(subject.activePlatforms, [ReleasePlatform.android]);
    });

    test('is empty on a release with no platforms', () {
      final subject = release();
      expect(subject.hasPlatform(ReleasePlatform.android), isFalse);
      expect(subject.statusFor(ReleasePlatform.android), isNull);
      expect(subject.isActiveOn(ReleasePlatform.android), isFalse);
      expect(subject.activePlatforms, isEmpty);
    });
  });
}
