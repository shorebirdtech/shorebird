import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(CancelSubscriptionResponse, () {
    test('can be (de)serialized', () {
      final response = CancelSubscriptionResponse(
        expirationDate: DateTime.now(),
      );
      expect(
        CancelSubscriptionResponse.fromJson(response.toJson()).toJson(),
        equals(response.toJson()),
      );
    });
  });
}
