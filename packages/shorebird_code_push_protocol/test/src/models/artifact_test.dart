import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('Artifact', () {
    test('can be (de)serialized', () {
      const artifact = Artifact(
        arch: 'aarm64',
        platform: 'android',
        url: 'https://example.com',
        hash: '#',
      );
      expect(
        Artifact.fromJson(artifact.toJson()).toJson(),
        equals(artifact.toJson()),
      );
    });
  });
}
