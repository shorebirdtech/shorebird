import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(CancelSubscriptionResponse, () {
    test('can be serialized to json', () {
      final time = DateTime.now();
      final response = CancelSubscriptionResponse(expirationDate: time);
      expect(
        response.toJson(),
        {'expiration_date': time.millisecondsSinceEpoch ~/ 1000},
      );
    });
  });
}
