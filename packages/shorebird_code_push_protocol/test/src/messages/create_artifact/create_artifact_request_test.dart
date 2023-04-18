import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(CreateArtifactRequest, () {
    test('can be (de)serialized', () {
      const request = CreateArtifactRequest(
        arch: 'arm64',
        platform: 'android',
        hash: '1234',
        size: 9876,
      );
      expect(
        CreateArtifactRequest.fromJson(request.toJson()).toJson(),
        equals(request.toJson()),
      );
    });
  });
}
