import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(UpdatePatchRequest, () {
    test('can be (de)serialized', () {
      const request = UpdatePatchRequest(
        notes: 'notes',
      );
      expect(
        UpdateReleaseRequest.fromJson(request.toJson()).toJson(),
        equals(request.toJson()),
      );
    });
  });
}
