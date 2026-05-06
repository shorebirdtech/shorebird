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

    test('can be (de)serialized with platforms, latestReleases, and '
        'pendingReleases', () {
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
              iconBase64: 'data:image/png;base64,AAA',
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
