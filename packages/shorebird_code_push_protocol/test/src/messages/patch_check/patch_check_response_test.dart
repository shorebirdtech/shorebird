import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(PatchCheckResponse, () {
    test('can be serialized to json without patch metadata', () {
      const response = PatchCheckResponse(patchAvailable: true);
      expect(response.toJson(), {
        'patch_available': true,
        'patch': null,
        'rolled_back_patch_numbers': null,
      });
    });

    test('can be serialized to json with patch metadata', () {
      const response = PatchCheckResponse(
        patchAvailable: true,
        patch: PatchCheckMetadata(
          number: 1,
          downloadUrl: 'https://download.com',
          hash: '1234',
          hashSignature: null,
        ),
      );
      expect(response.toJson(), {
        'patch_available': true,
        'patch': {
          'number': 1,
          'download_url': 'https://download.com',
          'hash': '1234',
        },
        'rolled_back_patch_numbers': null,
      });
    });

    group('when there is a hash signature', () {
      test('includes the signature', () {
        const response = PatchCheckResponse(
          patchAvailable: true,
          patch: PatchCheckMetadata(
            number: 1,
            downloadUrl: 'https://download.com',
            hash: '1234',
            hashSignature: 'signature',
          ),
        );
        expect(response.toJson(), {
          'patch_available': true,
          'patch': {
            'number': 1,
            'download_url': 'https://download.com',
            'hash': '1234',
            'hash_signature': 'signature',
          },
          'rolled_back_patch_numbers': null,
        });
      });
    });

    group('when rolled back patch numbers are provided', () {
      test('includes the rolled back patch numbers', () {
        const response = PatchCheckResponse(
          patchAvailable: true,
          rolledBackPatchNumbers: [1, 2, 3],
        );
        expect(response.toJson(), {
          'patch_available': true,
          'patch': null,
          'rolled_back_patch_numbers': [1, 2, 3],
        });
      });
    });
  });
}
