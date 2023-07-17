import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(UpdateReleaseRequest, () {
    test('can be (de)serialized', () {
      const request = UpdateReleaseRequest(
        platform: 'android',
        status: ReleaseStatus.active,
      );
      expect(
        UpdateReleaseRequest.fromJson(request.toJson()).toJson(),
        equals(request.toJson()),
      );
    });
  });
}
