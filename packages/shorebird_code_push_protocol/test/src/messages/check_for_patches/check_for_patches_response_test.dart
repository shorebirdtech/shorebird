import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(CancelSubscriptionResponse, () {
    test('can be serialized to json without patch metadata', () {
      const response = CheckForPatchesResponse(patchAvailable: true);
      expect(response.toJson(), {'patch_available': true, 'patch': null});
    });

    test('can be serialized to json with patch metadata', () {
      const response = CheckForPatchesResponse(
        patchAvailable: true,
        patch: PatchMetadata(
          number: 1,
          downloadUrl: 'https://download.com',
          hash: '1234',
        ),
      );
      expect(
        response.toJson(),
        {
          'patch_available': true,
          'patch': {
            'number': 1,
            'download_url': 'https://download.com',
            'hash': '1234',
          },
        },
      );
    });
  });
}
