import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(CreatePatchRequest, () {
    test('can be (de)serialized', () {
      const request = CreatePatchRequest(
        releaseId: 1234,
        metadata: {'foo': 'bar'},
      );
      expect(
        CreatePatchRequest.fromJson(request.toJson()).toJson(),
        equals(request.toJson()),
      );
    });

    test('can be (de)serialized without metadata', () {
      const request = CreatePatchRequest(
        releaseId: 1234,
        metadata: {'foo': 'bar'},
      );
      expect(
        CreatePatchRequest.fromJson(request.toJson()).toJson(),
        equals(request.toJson()),
      );
    });
  });
}
