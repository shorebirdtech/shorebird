import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(CheckForPatchesRequest, () {
    test('can be (de)serialized', () {
      const request = CheckForPatchesRequest(
        releaseVersion: '1',
        patchNumber: 2,
        patchHash: '3',
        platform: 'android',
        arch: 'arm64',
        appId: 'app_123',
        channel: 'channel_123',
      );
      expect(
        CheckForPatchesRequest.fromJson(request.toJson()).toJson(),
        equals(request.toJson()),
      );
    });
  });
}
