import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(RollbackPatchRequest, () {
    test('can be (de)serialized with platforms', () {
      const request = RollbackPatchRequest(
        platforms: [ReleasePlatform.ios],
      );
      final json = request.toJson();
      expect(json['platforms'], equals(['ios']));
      expect(RollbackPatchRequest.fromJson(json), equals(request));
    });

    test('omits platforms when null', () {
      const request = RollbackPatchRequest();
      expect(request.toJson(), isNot(contains('platforms')));
      expect(RollbackPatchRequest.fromJson(request.toJson()), equals(request));
    });
  });
}
