import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(PromotePatchRequest, () {
    test('can be (de)serialized', () {
      const request = PromotePatchRequest(channelId: 123, patchId: 456);
      expect(
        PromotePatchRequest.fromJson(request.toJson()).toJson(),
        equals(request.toJson()),
      );
    });
  });
}
