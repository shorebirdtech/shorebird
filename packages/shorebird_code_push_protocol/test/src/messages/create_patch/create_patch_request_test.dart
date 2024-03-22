import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(CreatePatchRequest, () {
    test('can be (de)serialized', () {
      const request = CreatePatchRequest(
        releaseId: 1234,
        wasForced: true,
        hasAssetChanges: true,
        hasNativeChanges: false,
        metadata: CreatePatchMetadata(
          usedIgnoreAssetChangesFlag: true,
          usedIgnoreNativeChangesFlag: false,
          hasAssetChanges: true,
          hasNativeChanges: false,
          environment: BuildEnvironmentMetadata(
            operatingSystem: 'linux',
            operatingSystemVersion: '1.0.0',
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
      const request = CreatePatchRequest(
        releaseId: 1234,
        wasForced: true,
        hasAssetChanges: true,
        hasNativeChanges: false,
        metadata: null,
      );
      expect(
        CreatePatchRequest.fromJson(request.toJson()).toJson(),
        equals(request.toJson()),
      );
    });
  });
}
