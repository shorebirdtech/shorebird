import 'package:stripe_api/stripe_api.dart';
import 'package:test/test.dart';

import '../../fixtures/stripe/stripe_fixtures.dart';

void main() {
  group(StripeEvent, () {
    test('deserializes checkout session event', () {
      final event = StripeEvent<StripeCheckoutSession>.fromJson(
        checkoutSessionCompletedEventJson,
      );
      expect(event.object, isA<StripeCheckoutSession>());
      expect(
        event.created,
        DateTime.fromMillisecondsSinceEpoch(1681743321 * 1000),
      );
    });

    test('deserializes subscription event', () {
      final event = StripeEvent<StripeSubscription>.fromJson(
        subscriptionCreatedEventJson,
      );
      expect(event.object, isA<StripeSubscription>());
      expect(
        event.created,
        DateTime.fromMillisecondsSinceEpoch(1681228056 * 1000),
      );
    });

    test('throws exception on unknown event type', () {
      expect(
        () => StripeEvent<dynamic>.fromJson({
          'id': 'evt_123',
          'created': 1681228056,
          'data': {
            'object': {'object': 'bogus.object'},
          },
        }),
        throwsA(isA<Exception>()),
      );
    });
  });
}
