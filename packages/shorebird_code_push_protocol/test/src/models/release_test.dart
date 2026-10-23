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

    test('carries its signing', () {
      final release = Release(
        id: 1,
        appId: 'app-id',
        version: '1.0.0',
        flutterRevision: '83305b5088e6fe327fb3334a73ff190828d85713',
        platformStatuses: const {},
        createdAt: DateTime(2023),
        updatedAt: DateTime(2023),
        signing: const ReleaseSigning(
          mode: 'managed',
          keyId: 7,
          publicKeyPem: 'pem',
        ),
      );
      final json = release.toJson();
      expect(json['signing'], {
        'mode': 'managed',
        'key_id': 7,
        'public_key_pem': 'pem',
      });
      final parsed = Release.fromJson(json);
      expect(parsed.signing, release.signing);
      expect(parsed.signing!.signingMode, ReleaseSigningMode.managed);
    });

    test('reads a signing mode it does not know as unknown', () {
      final json = Release(
        id: 1,
        appId: 'app-id',
        version: '1.0.0',
        flutterRevision: '83305b5088e6fe327fb3334a73ff190828d85713',
        platformStatuses: const {},
        createdAt: DateTime(2023),
        updatedAt: DateTime(2023),
      ).toJson()..['signing'] = {'mode': 'hardware'};
      final parsed = Release.fromJson(json);
      expect(parsed.signing!.mode, 'hardware');
      expect(parsed.signing!.signingMode, isNull);
    });

    test('omits signing for a release that predates it', () {
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
      expect(json.containsKey('signing'), isFalse);
      expect(Release.fromJson(json).signing, isNull);
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
