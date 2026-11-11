import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(RollforwardPatchRequest, () {
    test('can be (de)serialized with platforms', () {
      const request = RollforwardPatchRequest(
        platforms: [ReleasePlatform.android],
      );
      final json = request.toJson();
      expect(json['platforms'], equals(['android']));
      expect(RollforwardPatchRequest.fromJson(json), equals(request));
    });
  });
}
