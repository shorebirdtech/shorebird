import 'package:decimal/decimal.dart';
import 'package:stripe_api/stripe_api.dart';
import 'package:test/test.dart';

import '../../fixtures/stripe/stripe_fixtures.dart';

void main() {
  group(StripePrice, () {
    group('(de)serialization', () {
      test('can be deserialized from json', () {
        final subscription = StripeSubscription.fromJson(subscriptionJson);
        final price = subscription.items.first.price;

        expect(price.id, 'price_1MvjPuHSA9cXarIcfmWAQo72');
        expect(price.productId, 'prod_Nh7fDKPeoghLht');
        expect(price.currency, 'usd');
        expect(price.billingScheme, BillingScheme.perUnit);
        expect(price.unitAmount, 1500);
        expect(price.unitAmountDecimal, Decimal.fromInt(1500));
        expect(price.tiers, isNull);
        expect(price.usageType, UsageType.licensed);
        expect(price.meterId, isNull);
      });

      test('can be deserialized from json (payg)', () {
        final subscriptionItem = StripeSubscriptionItem.fromJson(
          payAsYouGoSubscriptionItemJson,
        );

        final price = subscriptionItem.price;
        expect(price.id, 'price_1Pm4YJHSA9cXarIcpDllPtvw');
        expect(price.productId, 'prod_QdLE0bb1qFBFMv');
        expect(price.currency, 'usd');
        expect(price.billingScheme, BillingScheme.perUnit);
        expect(price.unitAmount, isNull);
        expect(price.unitAmountDecimal, Decimal.parse('0.04'));
        expect(price.tiers, isNull);
        expect(price.usageType, UsageType.metered);
        expect(price.meterId, 'mtr_test_61QvSUDTnLya5cdwG41HSA9cXarIc144');
      });
    });

    group('StripePriceTiers', () {
      const fiftyThousandTier = StripePriceTier(
        flatAmount: 2000,
        flatAmountDecimal: '2000',
        unitAmount: null,
        unitAmountDecimal: null,
        upTo: 50000,
      );
      const threeHundredThousandTier = StripePriceTier(
        flatAmount: 10000,
        flatAmountDecimal: '1000',
        unitAmount: null,
        unitAmountDecimal: null,
        upTo: 300000,
      );
      const oneMillionTier = StripePriceTier(
        flatAmount: 30000,
        flatAmountDecimal: '30000',
        unitAmount: null,
        unitAmountDecimal: null,
        upTo: 1000000,
      );
      const twoAndAHalfMillionTier = StripePriceTier(
        flatAmount: 70000,
        flatAmountDecimal: '70000',
        unitAmount: null,
        unitAmountDecimal: null,
        upTo: 2500000,
      );
      const fiveMillionTier = StripePriceTier(
        flatAmount: 125000,
        flatAmountDecimal: '125000',
        unitAmount: null,
        unitAmountDecimal: null,
        upTo: 5000000,
      );
      const tenMillionTier = StripePriceTier(
        flatAmount: 200000,
        flatAmountDecimal: '200000',
        unitAmount: null,
        unitAmountDecimal: null,
        upTo: 10000000,
      );
      const maxTier = StripePriceTier(
        flatAmount: 500000,
        flatAmountDecimal: '500000',
        unitAmount: null,
        unitAmountDecimal: null,
        upTo: null,
      );

      late List<StripePriceTier> tiers;

      setUp(() {
        tiers = [
          fiftyThousandTier,
          threeHundredThousandTier,
          oneMillionTier,
          twoAndAHalfMillionTier,
          fiveMillionTier,
          tenMillionTier,
          maxTier,
        ];
      });

      test('tierForQuantity returns the correct tier', () {
        final price = StripePrice(
          id: 'test-price-id',
          productId: 'test-product-id',
          currency: 'usd',
          billingScheme: BillingScheme.tiered,
          tiers: tiers,
        );

        // Values equal to a tier's [upTo] field should return that tier.
        expect(price.tierForQuantity(50000), fiftyThousandTier);
        expect(price.tierForQuantity(300000), threeHundredThousandTier);
        expect(price.tierForQuantity(1000000), oneMillionTier);
        expect(price.tierForQuantity(2500000), twoAndAHalfMillionTier);
        expect(price.tierForQuantity(5000000), fiveMillionTier);
        expect(price.tierForQuantity(10000000), tenMillionTier);

        // Values between two tiers' [upTo] fields should return the higher
        // tier.
        expect(price.tierForQuantity(40000), fiftyThousandTier);
        expect(price.tierForQuantity(2000000), twoAndAHalfMillionTier);
        expect(price.tierForQuantity(2500001), fiveMillionTier);

        // Values above any tier's [upTo] field should return the last bounded
        // tier.
        expect(price.tierForQuantity(99999999), tenMillionTier);
      });

      group('when tiers are shuffled', () {
        setUp(() {
          tiers.shuffle();
        });

        test('tierForQuantity returns the correct tier', () {
          final price = StripePrice(
            id: 'test-price-id',
            productId: 'test-product-id',
            currency: 'usd',
            billingScheme: BillingScheme.tiered,
            tiers: tiers,
          );

          // Values equal to a tier's [upTo] field should return that tier.
          expect(price.tierForQuantity(50000), fiftyThousandTier);
          expect(price.tierForQuantity(300000), threeHundredThousandTier);
          expect(price.tierForQuantity(1000000), oneMillionTier);
          expect(price.tierForQuantity(2500000), twoAndAHalfMillionTier);
          expect(price.tierForQuantity(5000000), fiveMillionTier);
          expect(price.tierForQuantity(10000000), tenMillionTier);

          // Values between two tiers' [upTo] fields should return the higher
          // tier.
          expect(price.tierForQuantity(40000), fiftyThousandTier);
          expect(price.tierForQuantity(2000000), twoAndAHalfMillionTier);
          expect(price.tierForQuantity(2500001), fiveMillionTier);

          // Values above any tier's [upTo] field should return the last bounded
          // tier.
          expect(price.tierForQuantity(99999999), tenMillionTier);
        });
      });
    });
  });
}
