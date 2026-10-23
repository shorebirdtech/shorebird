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

    test('carries its signing mode and key', () {
      final release = Release(
        id: 1,
        appId: 'app-id',
        version: '1.0.0',
        flutterRevision: '83305b5088e6fe327fb3334a73ff190828d85713',
        platformStatuses: const {},
        createdAt: DateTime(2023),
        updatedAt: DateTime(2023),
        signingMode: ReleaseSigningMode.managed,
        signingKeyId: 7,
      );
      final json = release.toJson();
      expect(json['signing_mode'], 'managed');
      expect(json['signing_key_id'], 7);
      final parsed = Release.fromJson(json);
      expect(parsed.signingMode, ReleaseSigningMode.managed);
      expect(parsed.signingKeyId, 7);
    });

    test('omits signing fields an older server leaves out', () {
      final release = Release(
        id: 1,
        appId: 'app-id',
        version: '1.0.0',
        flutterRevision: '83305b5088e6fe327fb3334a73ff190828d85713',
        platformStatuses: const {},
        createdAt: DateTime(2023),
        updatedAt: DateTime(2023),
      );
      final json = release.toJson();
      expect(json.containsKey('signing_mode'), isFalse);
      expect(json.containsKey('signing_key_id'), isFalse);
      expect(Release.fromJson(json).signingMode, isNull);
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
  });
}
