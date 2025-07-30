import 'package:stripe_api/stripe_api.dart';
import 'package:test/test.dart';

import '../../fixtures/stripe/stripe_fixtures.dart';

void main() {
  group(StripeCustomer, () {
    test('deserializes from json', () {
      final customer = StripeCustomer.fromJson(customerJson);

      expect(customer.id, 'cus_123');
      expect(customer.name, 'Jane Doe');
      expect(customer.email, 'test@shorebird.dev');
      expect(customer.subscriptions, null);

      expect(
        customer.toString(),
        equals('Jane Doe - test@shorebird.dev (id:cus_123)'),
      );
    });

    test('deserializes from list with expanded subscriptions', () {
      final data =
          customerSearchOneResultWithExpandedSubscriptionsJson['data'] as List;
      final customerJson = data.first as Map<String, dynamic>;
      final customer = StripeCustomer.fromJson(customerJson);

      expect(customer.id, 'cus_123');
      expect(customer.name, 'Jane Doe');
      expect(customer.email, 'test@shorebird.dev');

      final subscriptions = customer.subscriptions;
      expect(subscriptions!.length, equals(1));

      final subscription = subscriptions.first;

      expect(subscription.id, equals('sub_1Mo9r2HSA9cXarIcVgf2GQt4'));
      expect(subscription.customer, equals('cus_123'));
      expect(subscription.status.name, equals('active'));
    });
  });
}
