import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(CreatePatchArtifactRequest, () {
    test('can be (de)serialized', () {
      const request = CreatePatchArtifactRequest(
        arch: 'arm64',
        platform: ReleasePlatform.android,
        hash: '1234',
        size: 9876,
      );
      expect(
        CreatePatchArtifactRequest.fromJson(request.toJson()).toJson(),
        equals(request.toJson()),
      );
    });

    group('when there is a hash signature', () {
      test('can be (de)serialized', () {
        const request = CreatePatchArtifactRequest(
          arch: 'arm64',
          platform: ReleasePlatform.android,
          hash: '1234',
          hashSignature: 'Shh',
          size: 9876,
        );
        final instance = CreatePatchArtifactRequest.fromJson(request.toJson());
        expect(instance.toJson(), equals(request.toJson()));
        expect(instance.hashSignature, equals('Shh'));
      });
    });

    test('can be (de)serialized with native lockfile hashes', () {
      const request = CreatePatchArtifactRequest(
        arch: 'arm64',
        platform: ReleasePlatform.ios,
        hash: '1234',
        size: 9876,
        podfileLockHash: 'podfile-lock-hash',
        packageResolvedHash: 'package-resolved-hash',
        pluginSwiftPackageHash: 'plugin-swift-package-hash',
      );
      final json = request.toJson();
      expect(json['package_resolved_hash'], equals('package-resolved-hash'));
      expect(
        json['plugin_swift_package_hash'],
        equals('plugin-swift-package-hash'),
      );
      expect(CreatePatchArtifactRequest.fromJson(json), equals(request));
    });
  });
}
