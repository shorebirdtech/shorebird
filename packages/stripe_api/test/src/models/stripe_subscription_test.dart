// cspell:words sub_1MvjPuHSA9cXarIcaWYNaezR cus_Nh7fUR7HHhO8xT
import 'package:stripe_api/stripe_api.dart';
import 'package:test/test.dart';

import '../../fixtures/stripe/stripe_fixtures.dart';

void main() {
  group(StripeSubscription, () {
    test('deserializes from json', () {
      final subscription = StripeSubscription.fromJson(subscriptionJson);

      expect(subscription.id, 'sub_1MvjPuHSA9cXarIcaWYNaezR');
      expect(subscription.cancelAtPeriodEnd, false);
      expect(
        subscription.canceledAt,
        DateTime.fromMillisecondsSinceEpoch(1683820054 * 1000),
      );
      expect(
        subscription.currentPeriodEnd,
        DateTime.fromMillisecondsSinceEpoch(1683820054 * 1000),
      );
      expect(
        subscription.currentPeriodStart,
        DateTime.fromMillisecondsSinceEpoch(1681228054 * 1000),
      );
      expect(subscription.customer, 'cus_Nh7fUR7HHhO8xT');
      expect(subscription.endedAt, null);
      expect(
        subscription.startDate,
        DateTime.fromMillisecondsSinceEpoch(1681228054 * 1000),
      );
      expect(subscription.status, StripeSubscriptionStatus.active);
      expect(subscription.trialStart, isNull);
      expect(subscription.trialEnd, isNull);
    });

    test('deserializes from json with missing items data', () {
      final updatedSubscriptionJson = subscriptionJson;
      (updatedSubscriptionJson['items'] as Map<String, dynamic>).remove('data');
      final subscription = StripeSubscription.fromJson(updatedSubscriptionJson);

      expect(subscription.items, isEmpty);
    });

    group('trial subscription', () {
      test('deserializes from json', () {
        final subscription = StripeSubscription.fromJson(
          trialingSubscriptionJson,
        );

        // cspell:disable-next-line
        expect(subscription.id, 'sub_1OL84vHSA9cXarIcNIxi0Xho');
        expect(subscription.cancelAtPeriodEnd, false);
        expect(subscription.currentPeriodEnd, isNotNull);
        expect(subscription.currentPeriodStart, isNotNull);
        // cspell:disable-next-line
        expect(subscription.customer, 'cus_NnCoUcv8aBXCA2');
        expect(subscription.endedAt, null);
        expect(subscription.startDate, isNotNull);
        expect(subscription.status, StripeSubscriptionStatus.trialing);
        expect(
          subscription.trialStart,
          DateTime.fromMillisecondsSinceEpoch(1725845719000),
        );
        expect(
          subscription.trialEnd,
          DateTime.fromMillisecondsSinceEpoch(1788053706000),
        );
        expect(subscription.isActiveOrTrial, isTrue);
      });
    });

    group('isActiveOrTrial', () {
      test('returns true if status is active', () {
        final subscription = StripeSubscription(
          id: 'sub_123',
          cancelAtPeriodEnd: false,
          currentPeriodEnd: DateTime.now(),
          currentPeriodStart: DateTime.now(),
          customer: 'cus_123',
          startDate: DateTime.now(),
          status: StripeSubscriptionStatus.active,
          items: [],
        );
        expect(subscription.isActiveOrTrial, isTrue);
      });

      test('returns true if subscription is trialing', () {
        final subscription = StripeSubscription.fromJson(
          trialingSubscriptionJson,
        );
        expect(subscription.isActiveOrTrial, isTrue);
      });

      test('returns false if status is not active', () {
        final subscription = StripeSubscription(
          id: 'sub_123',
          cancelAtPeriodEnd: false,
          currentPeriodEnd: DateTime.now(),
          currentPeriodStart: DateTime.now(),
          customer: 'cus_123',
          startDate: DateTime.now(),
          status: StripeSubscriptionStatus.canceled,
          items: [],
        );
        expect(subscription.isActiveOrTrial, isFalse);
      });
    });

    group('totalCost', () {
      test('returns 0 if subscription contains no items', () {
        final subscription = StripeSubscription(
          id: 'sub_123',
          cancelAtPeriodEnd: false,
          currentPeriodEnd: DateTime.now(),
          currentPeriodStart: DateTime.now(),
          customer: 'cus_123',
          startDate: DateTime.now(),
          status: StripeSubscriptionStatus.active,
          items: [],
        );
        expect(subscription.totalCost, 0);
      });

      test('returns sum of item costs', () {
        final subscription = StripeSubscription(
          id: 'sub_123',
          cancelAtPeriodEnd: false,
          currentPeriodEnd: DateTime.now(),
          currentPeriodStart: DateTime.now(),
          customer: 'cus_123',
          startDate: DateTime.now(),
          status: StripeSubscriptionStatus.active,
          items: [
            const StripeSubscriptionItem(
              id: 'item_1',
              price: StripePrice(
                id: 'price_1',
                currency: 'usd',
                productId: 'prod_123',
                unitAmount: 1000,
                billingScheme: BillingScheme.perUnit,
              ),
              quantity: 1000,
            ),
            const StripeSubscriptionItem(
              id: 'item_2',
              price: StripePrice(
                id: 'price_2',
                currency: 'usd',
                productId: 'prod_123',
                unitAmount: 2000,
                billingScheme: BillingScheme.perUnit,
              ),
              quantity: 1000,
            ),
            const StripeSubscriptionItem(
              id: 'item_3',
              price: StripePrice(
                id: 'price_3',
                currency: 'usd',
                productId: 'prod_123',
                unitAmount: 3000,
                billingScheme: BillingScheme.perUnit,
              ),
              quantity: 1000,
            ),
          ],
        );
        expect(subscription.totalCost, 6000);
      });
    });

    group('hasMeteredBilling', () {
      late StripeSubscription subscription;

      group("when a subscription item's price has a metered usage type", () {
        setUp(() {
          final subscriptionItem = StripeSubscriptionItem.fromJson(
            payAsYouGoSubscriptionItemJson,
          );
          subscription = StripeSubscription(
            id: 'sub_123',
            cancelAtPeriodEnd: false,
            currentPeriodEnd: DateTime.now(),
            currentPeriodStart: DateTime.now(),
            customer: 'cus_123',
            startDate: DateTime.now(),
            status: StripeSubscriptionStatus.active,
            items: [subscriptionItem],
          );
        });

        test('returns true', () {
          expect(subscription.hasMeteredBilling, isTrue);
        });
      });

      group("when no subscription item's price has a metered usage type", () {
        setUp(() {
          subscription = StripeSubscription.fromJson(subscriptionJson);
        });

        test('returns false', () {
          expect(subscription.hasMeteredBilling, isFalse);
        });
      });
    });
  });
}
