import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(Release, () {
    test('can be (de)serialized', () {
      final release = Release(
        id: 1,
        appId: 'app-id',
        version: '1.0.0',
        flutterRevision: '83305b5088e6fe327fb3334a73ff190828d85713',
        flutterVersion: '3.22.0',
        displayName: 'v1.0.0',
        platformStatuses: const {ReleasePlatform.android: ReleaseStatus.active},
        notes: 'some notes',
        createdAt: DateTime(2023),
        updatedAt: DateTime(2023),
      );
      expect(
        Release.fromJson(release.toJson()).toJson(),
        equals(release.toJson()),
      );
    });

    test('is equatable', () {
      final release1 = Release(
        id: 1,
        appId: 'app-id',
        version: '1.0.0',
        flutterRevision: '83305b5088e6fe327fb3334a73ff190828d85713',
        flutterVersion: '3.22.0',
        displayName: 'v1.0.0',
        platformStatuses: const {ReleasePlatform.android: ReleaseStatus.active},
        notes: 'some notes',
        createdAt: DateTime(2023),
        updatedAt: DateTime(2023),
      );
      final release1Copy = Release(
        id: 1,
        appId: 'app-id',
        version: '1.0.0',
        flutterRevision: '83305b5088e6fe327fb3334a73ff190828d85713',
        flutterVersion: '3.22.0',
        displayName: 'v1.0.0',
        platformStatuses: const {ReleasePlatform.android: ReleaseStatus.active},
        notes: 'some notes',
        createdAt: DateTime(2023),
        updatedAt: DateTime(2023),
      );
      final release2 = Release(
        id: 2,
        appId: 'app-id',
        version: '1.0.0+1',
        flutterRevision: '83305b5088e6fe327fb3334a73ff190828d85713',
        flutterVersion: '3.22.0',
        displayName: 'v1.0.0',
        platformStatuses: const {ReleasePlatform.android: ReleaseStatus.active},
        notes: 'some notes',
        createdAt: DateTime(2023),
        updatedAt: DateTime(2023),
      );

      expect(release1, equals(release1Copy));
      expect(release1, isNot(equals(release2)));
    });

    group('platforms', () {
      Map<String, dynamic> releaseJson({Object? platforms}) => {
        'id': 1,
        'app_id': 'app-id',
        'version': '1.0.0',
        'flutter_revision': '83305b5088e6fe327fb3334a73ff190828d85713',
        'platform_statuses': {'android': 'active', 'ios': 'draft'},
        'platforms': ?platforms,
        'created_at': '2023-01-01T00:00:00.000Z',
        'updated_at': '2023-01-01T00:00:00.000Z',
      };

      test('reads each platform with its status and signing', () {
        final release = Release.fromJson(
          releaseJson(
            platforms: [
              {
                'platform': 'android',
                'status': 'active',
                'signing_mode': 'managed',
              },
              {'platform': 'ios', 'status': 'draft'},
            ],
          ),
        );
        expect(release.platforms, const [
          ReleasePlatformDetails(
            platform: ReleasePlatform.android,
            status: ReleaseStatus.active,
            signingMode: 'managed',
          ),
          ReleasePlatformDetails(
            platform: ReleasePlatform.ios,
            status: ReleaseStatus.draft,
          ),
        ]);
        expect(Release.fromJson(release.toJson()), equals(release));
      });

      test('reads a signing mode added later as an unknown string', () {
        final release = Release.fromJson(
          releaseJson(
            platforms: [
              {
                'platform': 'android',
                'status': 'active',
                'signing_mode': 'quantum',
              },
            ],
          ),
        );
        expect(release.platforms!.single.signingMode, equals('quantum'));
      });

      test('is null, and omitted, when the server sends none', () {
        final release = Release.fromJson(releaseJson());
        expect(release.platforms, isNull);
        expect(release.toJson(), isNot(contains('platforms')));
      });
    });
  });
}
