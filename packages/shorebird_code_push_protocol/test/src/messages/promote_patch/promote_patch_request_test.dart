import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(PromotePatchRequest, () {
    test('can be (de)serialized', () {
      const request = PromotePatchRequest(channelId: 123, patchId: 456);
      expect(request.toJson(), isNot(contains('rollout_percentage')));
      expect(
        PromotePatchRequest.fromJson(request.toJson()),
        equals(request),
      );
    });

    test('can be (de)serialized with rolloutPercentage', () {
      const request = PromotePatchRequest(
        channelId: 123,
        patchId: 456,
        rolloutPercentage: 25.5,
      );
      final json = request.toJson();
      expect(json['rollout_percentage'], equals(25.5));
      expect(PromotePatchRequest.fromJson(json), equals(request));
    });
  });
}
