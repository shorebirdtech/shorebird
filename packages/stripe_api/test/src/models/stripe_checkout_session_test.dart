import 'package:stripe_api/stripe_api.dart';
import 'package:test/test.dart';

import '../../fixtures/stripe/stripe_fixtures.dart';

void main() {
  group(StripeCheckoutSession, () {
    test('deserializes from json', () async {
      final sessionEvent = StripeEvent<StripeCheckoutSession>.fromJson(
        checkoutSessionCompletedEventJson,
      );
      final session = sessionEvent.object;
      expect(session.customerId, 'cus_123');
      expect(session.metadata, {'shorebird_email': 'tester@shorebird.dev'});
    });
  });
}
