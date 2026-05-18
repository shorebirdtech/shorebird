import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(PatchCheckResponse, () {
    test('uses value equality', () {
      expect(
        // Ignoring for value quality testing.
        const PatchCheckResponse(patchAvailable: true),
        // Ignoring for value quality testing.
        equals(const PatchCheckResponse(patchAvailable: true)),
      );
    });

    test('can be (de)serialized', () {
      const response = PatchCheckResponse(patchAvailable: true);
      expect(
        PatchCheckResponse.fromJson(response.toJson()).toJson(),
        equals(response.toJson()),
      );
    });

    test('can be serialized to json without patch metadata', () {
      const response = PatchCheckResponse(patchAvailable: true);
      expect(response.toJson(), {
        'patch_available': true,
        'patch': null,
        'rolled_back_patch_numbers': null,
        'available_release_versions': null,
      });
    });

    test('PatchCheckMetadata uses value equality', () {
      expect(
        // Ignoring for value quality testing.
        const PatchCheckMetadata(
          number: 1,
          downloadUrl: 'https://download.com',
          hash: '1234',
        ),
        equals(
          // Ignoring for value quality testing.
          const PatchCheckMetadata(
            number: 1,
            downloadUrl: 'https://download.com',
            hash: '1234',
          ),
        ),
      );
    });

    test('PatchCheckMetadata can be (de)serialized', () {
      const metadata = PatchCheckMetadata(
        number: 1,
        downloadUrl: 'https://download.com',
        hash: '1234',
      );
      expect(
        PatchCheckMetadata.fromJson(metadata.toJson()).toJson(),
        equals(metadata.toJson()),
      );
    });

    test('can be serialized to json with patch metadata', () {
      const response = PatchCheckResponse(
        patchAvailable: true,
        patch: PatchCheckMetadata(
          number: 1,
          downloadUrl: 'https://download.com',
          hash: '1234',
        ),
      );
      // Generated code always emits nullable fields as `null` rather than
      // dropping them. Wire-equivalent for JSON consumers that treat
      // absent == null.
      expect(response.toJson(), {
        'patch_available': true,
        'patch': {
          'number': 1,
          'download_url': 'https://download.com',
          'hash': '1234',
          'hash_signature': null,
        },
        'rolled_back_patch_numbers': null,
        'available_release_versions': null,
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
          'available_release_versions': null,
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
          'available_release_versions': null,
        });
      });

      test('parses the rolled back patch numbers from json', () {
        final response = PatchCheckResponse.fromJson(const {
          'patch_available': true,
          'rolled_back_patch_numbers': [1, 2, 3],
        });
        expect(response.rolledBackPatchNumbers, equals([1, 2, 3]));
      });
    });

    group('when available release versions are provided', () {
      test('includes the available release versions', () {
        const response = PatchCheckResponse(
          patchAvailable: false,
          availableReleaseVersions: ['1.0.1+2', '1.0.2+3'],
        );
        expect(response.toJson(), {
          'patch_available': false,
          'patch': null,
          'rolled_back_patch_numbers': null,
          'available_release_versions': ['1.0.1+2', '1.0.2+3'],
        });
      });

      test('parses available release versions from json', () {
        final response = PatchCheckResponse.fromJson(const {
          'patch_available': false,
          'available_release_versions': ['1.0.1+2', '1.0.2+3'],
        });
        expect(
          response.availableReleaseVersions,
          equals(['1.0.1+2', '1.0.2+3']),
        );
      });
    });
  });
}
