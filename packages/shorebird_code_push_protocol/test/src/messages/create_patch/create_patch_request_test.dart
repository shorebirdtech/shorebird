import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(CreatePatchRequest, () {
    test('can be (de)serialized', () {
      const request = CreatePatchRequest(
        releaseId: 1234,
        wasForced: true,
        metadata: CreatePatchMetadata(
          releasePlatform: ReleasePlatform.android,
          usedIgnoreAssetChangesFlag: true,
          usedIgnoreNativeChangesFlag: false,
          hasAssetChanges: true,
          hasNativeChanges: false,
          linkPercentage: 99.9,
          environment: BuildEnvironmentMetadata(
            operatingSystem: 'linux',
            operatingSystemVersion: '1.0.0',
            shorebirdVersion: '1.2.3',
            xcodeVersion: null,
          ),
        ),
      );
      expect(
        CreatePatchRequest.fromJson(request.toJson()).toJson(),
        equals(request.toJson()),
      );
    });

    test('can be (de)serialized without metadata', () {
      final request = CreatePatchRequest(
        releaseId: 1234,
        wasForced: true,
        metadata: CreatePatchMetadata.forTest(),
      );
      expect(
        CreatePatchRequest.fromJson(request.toJson()).toJson(),
        equals(request.toJson()),
      );
    });
  });
}
