import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(CreateReleaseRequest, () {
    test('can be (de)serialized', () {
      const request = CreateReleaseRequest(
        version: '1.2.3',
        flutterRevision: 'abc123',
        flutterVersion: '3.22.0',
        displayName: 'display_name',
      );
      expect(
        CreateReleaseRequest.fromJson(request.toJson()).toJson(),
        equals(request.toJson()),
      );
    });

    test('carries the managed key the CLI embedded', () {
      const request = CreateReleaseRequest(
        version: '1.2.3',
        flutterRevision: 'abc123',
        signing: ReleaseSigningRequest(
          mode: ReleaseSigningMode.managed,
          keyId: 7,
        ),
      );
      final json = request.toJson();
      expect(json['signing'], {'mode': 'managed', 'key_id': 7});
      expect(CreateReleaseRequest.fromJson(json), equals(request));
    });

    test("carries the customer's public key the CLI embedded", () {
      const request = CreateReleaseRequest(
        version: '1.2.3',
        flutterRevision: 'abc123',
        signing: ReleaseSigningRequest(
          mode: ReleaseSigningMode.customer,
          publicKeyPem: 'pem',
        ),
      );
      final json = request.toJson();
      expect(json['signing'], {'mode': 'customer', 'public_key_pem': 'pem'});
      expect(CreateReleaseRequest.fromJson(json), equals(request));
    });
  });
}
