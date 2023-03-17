import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('PatchArtifact', () {
    test('can be (de)serialized', () {
      const patchArtifact = PatchArtifact(
        patchNumber: 1,
        downloadUrl: 'https://example.com',
        hash: '#',
      );
      expect(
        PatchArtifact.fromJson(patchArtifact.toJson()).toJson(),
        equals(patchArtifact.toJson()),
      );
    });
  });
}
