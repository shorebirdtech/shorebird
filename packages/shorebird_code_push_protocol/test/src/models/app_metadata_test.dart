import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(AppMetadata, () {
    test('can be (de)serialized', () {
      final appMetadata = AppMetadata(
        appId: '30370f27-dbf1-4673-8b20-fb096e38dffa',
        displayName: 'My App',
        latestReleaseVersion: '1.0.0',
        latestPatchNumber: 1,
        createdAt: DateTime(2022),
        updatedAt: DateTime(2023),
      );
      expect(
        AppMetadata.fromJson(appMetadata.toJson()).toJson(),
        equals(appMetadata.toJson()),
      );
    });

    test('round-trips archivedAt as UTC, and omits it when null', () {
      final archivedAt = DateTime.utc(2026, 10, 16, 12, 30);
      final appMetadata = AppMetadata(
        appId: '30370f27-dbf1-4673-8b20-fb096e38dffa',
        displayName: 'My App',
        createdAt: DateTime.utc(2022),
        updatedAt: DateTime.utc(2023),
        archivedAt: archivedAt,
      );
      final json = appMetadata.toJson();
      expect(json['archived_at'], equals('2026-10-16T12:30:00.000Z'));
      expect(AppMetadata.fromJson(json).archivedAt, equals(archivedAt));
      expect(
        AppMetadata(
          appId: appMetadata.appId,
          displayName: appMetadata.displayName,
          createdAt: appMetadata.createdAt,
          updatedAt: appMetadata.updatedAt,
        ).toJson(),
        isNot(contains('archived_at')),
      );
    });

    test('can be (de)serialized with platforms, latestReleases, '
        'pendingReleases, and iconUrl', () {
      final appMetadata = AppMetadata(
        appId: '30370f27-dbf1-4673-8b20-fb096e38dffa',
        displayName: 'My App',
        latestReleaseVersion: '1.0.0',
        latestPatchNumber: 1,
        createdAt: DateTime(2022),
        updatedAt: DateTime(2023),
        platforms: const [ReleasePlatform.android, ReleasePlatform.ios],
        latestReleases: {
          ReleasePlatform.android: LatestRelease(
            id: 535,
            version: '1.2.3+5',
            flutterRevision: 'abc123',
            flutterVersion: '3.27.0',
            createdAt: DateTime(2023),
            updatedAt: DateTime(2023),
            status: ReleaseStatus.active,
            analysis: const ReleaseAnalysis(
              displayName: 'My App',
              packageName: 'com.example.app',
              minSdkVersion: '24',
              targetSdkVersion: '34',
              architectures: ['arm64-v8a'],
            ),
          ),
        },
        pendingReleases: {
          ReleasePlatform.ios: PendingRelease(
            id: 700,
            version: '1.2.4+6',
            createdAt: DateTime(2024),
          ),
        },
        iconUrl: '/api/v1/app-icons/30370f27-dbf1-4673-8b20-fb096e38dffa?v=535',
      );
      expect(
        AppMetadata.fromJson(appMetadata.toJson()).toJson(),
        equals(appMetadata.toJson()),
      );
    });

    group('equality', () {
      test('should return true if all properties are equal', () {
        final appMetadata1 = AppMetadata(
          appId: '30370f27-dbf1-4673-8b20-fb096e38dffa',
          displayName: 'My App',
          latestReleaseVersion: '1.0.0',
          latestPatchNumber: 1,
          createdAt: DateTime(2022),
          updatedAt: DateTime(2023),
        );

        final appMetadata2 = AppMetadata(
          appId: '30370f27-dbf1-4673-8b20-fb096e38dffa',
          displayName: 'My App',
          latestReleaseVersion: '1.0.0',
          latestPatchNumber: 1,
          createdAt: DateTime(2022),
          updatedAt: DateTime(2023),
        );

        expect(appMetadata1, equals(appMetadata2));
      });

      test('should return false if not all properties are equal', () {
        final appMetadata1 = AppMetadata(
          appId: '30370f27-dbf1-4673-8b20-fb096e38dffa',
          displayName: 'My App',
          latestReleaseVersion: '1.0.0',
          latestPatchNumber: 1,
          createdAt: DateTime(2022),
          updatedAt: DateTime(2023),
        );

        final appMetadata2 = AppMetadata(
          appId: 'deadbeef',
          displayName: 'My App',
          latestReleaseVersion: '1.0.0',
          latestPatchNumber: 1,
          createdAt: DateTime(2022),
          updatedAt: DateTime(2023),
        );

        expect(appMetadata1, isNot(equals(appMetadata2)));
      });
    });
  });
}
