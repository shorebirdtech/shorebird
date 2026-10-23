import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(CreateReleaseArtifactRequest, () {
    test('can be (de)serialized', () {
      const request = CreateReleaseArtifactRequest(
        arch: 'arm64',
        platform: ReleasePlatform.android,
        hash: '1234',
        size: 9876,
        canSideload: true,
        filename: 'test.apk',
      );
      expect(
        CreateReleaseArtifactRequest.fromJson(request.toJson()).toJson(),
        equals(request.toJson()),
      );
    });

    test('carries the managed key the binary embeds', () {
      const request = CreateReleaseArtifactRequest(
        arch: 'arm64',
        platform: ReleasePlatform.android,
        hash: '1234',
        size: 9876,
        filename: 'test.apk',
        signing: ArtifactSigningRequest(
          mode: ReleaseSigningMode.managed,
          keyId: 7,
        ),
      );
      final json = request.toJson();
      expect(json['signing'], {'mode': 'managed', 'key_id': 7});
      expect(CreateReleaseArtifactRequest.fromJson(json), equals(request));
    });

    test('carries only the mode for a customer-signed binary', () {
      const request = CreateReleaseArtifactRequest(
        arch: 'arm64',
        platform: ReleasePlatform.android,
        hash: '1234',
        size: 9876,
        filename: 'test.apk',
        signing: ArtifactSigningRequest(mode: ReleaseSigningMode.customer),
      );
      final json = request.toJson();
      expect(json['signing'], {'mode': 'customer'});
      expect(CreateReleaseArtifactRequest.fromJson(json), equals(request));
    });
  });
}
