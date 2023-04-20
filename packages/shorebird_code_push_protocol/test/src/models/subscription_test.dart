import 'package:shorebird_code_push_protocol/src/models/models.dart';
import 'package:test/test.dart';

void main() {
  group(Subscription, () {
    test('can be (de)serialized', () {
      final subscription = Subscription(
        cost: 100,
        paidThroughDate: DateTime.now(),
        willRenew: true,
      );
      expect(
        Subscription.fromJson(subscription.toJson()).toJson(),
        equals(subscription.toJson()),
      );
    });
  });
}
