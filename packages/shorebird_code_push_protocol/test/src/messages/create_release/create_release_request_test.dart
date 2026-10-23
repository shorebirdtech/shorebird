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

    test('carries its signing mode and key through JSON', () {
      const request = CreateReleaseRequest(
        version: '1.2.3',
        flutterRevision: 'abc123',
        signingMode: ReleaseSigningMode.managed,
        signingKeyId: 7,
      );
      final json = request.toJson();
      expect(json['signing_mode'], 'managed');
      expect(json['signing_key_id'], 7);
      expect(CreateReleaseRequest.fromJson(json), equals(request));
    });

    test('omits the signing fields when unset', () {
      const request = CreateReleaseRequest(
        version: '1.2.3',
        flutterRevision: 'abc123',
      );
      expect(request.toJson().keys, isNot(contains('signing_mode')));
      expect(request.toJson().keys, isNot(contains('signing_key_id')));
    });
  });
}
