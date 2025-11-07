import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:stripe_api/stripe_api.dart';
import 'package:test/test.dart';

import '../fixtures/stripe/stripe_fixtures.dart';

class _MockHttpClient extends Mock implements http.Client {}

void main() {
  group(StripeApi, () {
    const expectedAuthHeaders = {
      HttpHeaders.authorizationHeader: 'Bearer secret',
    };

    late http.Client httpClient;
    late StripeApi stripeApi;

    setUpAll(() {
      registerFallbackValue(Uri.parse('https://www.google.com/'));
    });

    setUp(() {
      httpClient = _MockHttpClient();
      stripeApi = StripeApi(client: httpClient, secretKey: 'secret');
    });

    test('can be instantiated without an explicit httpClient', () {
      expect(() => StripeApi(secretKey: 'secret'), returnsNormally);
    });

    group('fetchActiveSubscriptions', () {
      final customerUri = Uri.parse(
        'https://api.stripe.com/v1/customers/cus_123?expand%5B%5D=subscriptions',
      );

      test('returns an empty list if the customer object is missing a '
          'subscriptions list', () async {
        when(
          () => httpClient.get(customerUri, headers: any(named: 'headers')),
        ).thenAnswer(
          (_) async => http.Response(customerJsonString, HttpStatus.ok),
        );

        final subscriptions = await stripeApi.fetchActiveOrTrialSubscriptions(
          customerId: 'cus_123',
        );

        expect(subscriptions, isEmpty);
      });

      test(
        'returns an empty list if the customer has no subscriptions',
        () async {
          when(
            () => httpClient.get(customerUri, headers: any(named: 'headers')),
          ).thenAnswer(
            (_) async => http.Response(
              customerWithEmptySubscriptionJsonString,
              HttpStatus.ok,
            ),
          );

          final subscriptions = await stripeApi.fetchActiveOrTrialSubscriptions(
            customerId: 'cus_123',
          );

          expect(subscriptions, isEmpty);
        },
      );

      test(
        "returns an empty list if customer's subscriptions are inactive",
        () async {
          when(
            () => httpClient.get(customerUri, headers: any(named: 'headers')),
          ).thenAnswer(
            (_) async => http.Response(
              customerWithInactiveSubscriptionJsonString,
              HttpStatus.ok,
            ),
          );

          final subscriptions = await stripeApi.fetchActiveOrTrialSubscriptions(
            customerId: 'cus_123',
          );

          expect(subscriptions, isEmpty);
        },
      );

      test('returns subscriptions if the customer has subscriptions', () async {
        when(
          () => httpClient.get(customerUri, headers: any(named: 'headers')),
        ).thenAnswer(
          (_) async =>
              http.Response(customerWithSubscriptionJsonString, HttpStatus.ok),
        );

        final subscriptions = await stripeApi.fetchActiveOrTrialSubscriptions(
          customerId: 'cus_123',
        );

        expect(subscriptions, isNotEmpty);
      });
    });

    group('fetchCustomer', () {
      final uri = Uri.parse(
        'https://api.stripe.com/v1/customers/cus_123?expand%5B%5D=subscriptions',
      );

      test('throws exception if Stripe returns a non-200 response', () {
        when(
          () => httpClient.get(uri, headers: any(named: 'headers')),
        ).thenAnswer(
          (_) async => http.Response('Not found', HttpStatus.notFound),
        );

        expect(
          () => stripeApi.fetchCustomer(customerId: 'cus_123'),
          throwsException,
        );

        verify(
          () => httpClient.get(uri, headers: expectedAuthHeaders),
        ).called(1);
      });

      test('returns a customer on successful request', () async {
        when(
          () => httpClient.get(uri, headers: any(named: 'headers')),
        ).thenAnswer(
          (_) async => http.Response(customerJsonString, HttpStatus.ok),
        );

        final customer = await stripeApi.fetchCustomer(customerId: 'cus_123');

        expect(customer, isNotNull);
        expect(customer.id, 'cus_123');

        verify(
          () => httpClient.get(uri, headers: expectedAuthHeaders),
        ).called(1);
      });
    });

    group('fetchSubscription', () {
      const subscriptionId = 'sub_123';
      final uri = Uri.parse(
        'https://api.stripe.com/v1/subscriptions/sub_123',
      ).replace(queryParameters: {'expand[]': 'items.data.price.tiers'});

      test('throws exception if Stripe returns a non-200 response', () async {
        when(
          () => httpClient.get(uri, headers: any(named: 'headers')),
        ).thenAnswer(
          (_) async => http.Response('Not found', HttpStatus.notFound),
        );

        expect(
          () => stripeApi.fetchSubscription(subscriptionId: subscriptionId),
          throwsException,
        );

        verify(
          () => httpClient.get(uri, headers: expectedAuthHeaders),
        ).called(1);
      });

      test('returns a subscription on successful request', () async {
        when(
          () => httpClient.get(uri, headers: any(named: 'headers')),
        ).thenAnswer(
          (_) async => http.Response(subscriptionJsonString, HttpStatus.ok),
        );

        final subscription = await stripeApi.fetchSubscription(
          subscriptionId: subscriptionId,
        );

        expect(subscription, isNotNull);
        // cspell:disable-next-line
        expect(subscription.id, 'sub_1MvjPuHSA9cXarIcaWYNaezR');
        expect(subscription.items.first.price.tiers, isNull);
      });

      test(
        'returns a subscription with pricing tiers on successful request',
        () async {
          when(
            () => httpClient.get(uri, headers: any(named: 'headers')),
          ).thenAnswer(
            (_) async => http.Response(
              subscriptionWithPricingTiersJsonString,
              HttpStatus.ok,
            ),
          );

          final subscription = await stripeApi.fetchSubscription(
            subscriptionId: subscriptionId,
          );

          expect(subscription, isNotNull);
          // cspell:disable-next-line
          expect(subscription.id, 'sub_1NzOsBHSA9cXarIchHmEjlmc');
          final tiers = subscription.items.first.price.tiers;
          expect(tiers, hasLength(7));
          expect(tiers?.first.flatAmount, 2000);
          expect(tiers?.first.upTo, 50000);
          expect(tiers?.last.upTo, isNull);
        },
      );
    });

    group('fetchBillingMeters', () {
      setUp(() {
        when(
          () => httpClient.get(
            Uri.parse(
              'https://api.stripe.com/v1/billing/meters?status=active&limit=100',
            ),
            headers: any(named: 'headers'),
          ),
        ).thenAnswer(
          (_) async => http.Response(
            billingMetersPageJsonString,
            HttpStatus.ok,
          ),
        );

        when(
          () => httpClient.get(
            Uri.parse(
              'https://api.stripe.com/v1/billing/meters?status=active&limit=100&starting_after=mtr_test_61QvSUDTnLya5cdwG41HSA9cXarIc144',
            ),
            headers: any(named: 'headers'),
          ),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({
              'object': 'list',
              'data': <Map<String, dynamic>>[],
              'has_more': false,
            }),
            HttpStatus.ok,
          ),
        );
      });

      test('returns a billing meter on successful request', () async {
        final billingMeters = await stripeApi.fetchActiveBillingMeters();
        expect(billingMeters, hasLength(1));

        final billingMeter = billingMeters.first;
        expect(billingMeter.id, 'mtr_test_61QvSUDTnLya5cdwG41HSA9cXarIc144');
        expect(billingMeter.displayName, 'Patch Installs');
        expect(billingMeter.eventName, 'patch_installs');
      });
    });

    group('createMeterEvent', () {
      final uri = Uri.parse('https://api.stripe.com/v1/billing/meter_events');

      setUp(() {
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer((_) async => http.Response('', HttpStatus.ok));
      });

      test('sends the correct request', () async {
        await stripeApi.createMeterEvent(
          customerId: 'cus_123',
          eventName: 'test_event',
          value: 100,
          timestamp: 1234,
        );

        verify(
          () => httpClient.post(
            uri,
            headers: expectedAuthHeaders,
            body: {
              'event_name': 'test_event',
              'timestamp': '1234',
              'payload[value]': '100',
              'payload[stripe_customer_id]': 'cus_123',
            },
          ),
        ).called(1);
      });

      group('when response has non-success status code', () {
        setUp(() {
          when(
            () => httpClient.post(
              any(),
              headers: any(named: 'headers'),
              body: any(named: 'body'),
            ),
          ).thenAnswer(
            (_) async => http.Response('Not found', HttpStatus.notFound),
          );
        });

        test('throws exception', () async {
          await expectLater(
            () => stripeApi.createMeterEvent(
              customerId: 'cus_123',
              eventName: 'my-event',
              value: 100,
            ),
            throwsException,
          );
        });
      });
    });

    group('getMeterEventSummaries', () {
      const customerId = 'cus_123';
      const meterId = 'mtr_test_61Qs4Xo4ZBeo0c8Em41HSA9cXarIc0Ho';
      const startTimestamp = 0;
      const endTimestamp = 60;

      setUp(() {
        when(
          () => httpClient.get(
            Uri.parse(
              'https://api.stripe.com/v1/billing/meters/mtr_test_61Qs4Xo4ZBeo0c8Em41HSA9cXarIc0Ho/event_summaries?customer=cus_123&start_time=0&end_time=60&limit=100',
            ),
            headers: any(named: 'headers'),
          ),
        ).thenAnswer(
          (_) async => http.Response(
            meterEventSummariesWithMorePagesJsonString,
            HttpStatus.ok,
          ),
        );

        when(
          () => httpClient.get(
            Uri.parse(
              'https://api.stripe.com/v1/billing/meters/mtr_test_61Qs4Xo4ZBeo0c8Em41HSA9cXarIc0Ho/event_summaries?customer=cus_123&start_time=0&end_time=60&limit=100&starting_after=mtrusg_test_6041HSA9cXarIc6U76ce6L359f4ft60m5Xl3ox5sv7bt6bJ5bx5Y459D4Xt2E17ko6M86kt7kV3bl5QJ3U87PA60g6kp3Dn3kL7Gu3HU5Xl3ox5sv7bt6bY4p52Dr7od3Hc71E6go4od4LJ6cC6UM4t17Lc3Ta6ky3fx2D33fu3LI3oD3bk3Cy3Cy',
            ),
            headers: any(named: 'headers'),
          ),
        ).thenAnswer(
          (_) async => http.Response(
            meterEventSummariesWithNoMorePagesJsonString,
            HttpStatus.ok,
          ),
        );
      });

      test('returns all pages of meter summaries', () async {
        final meterEventSummary1 = StripeMeterEventSummary.fromJson(
          // Ignoring dynamic call for testing purposes.
          // ignore: avoid_dynamic_calls
          meterEventSummariesWithMorePagesJson['data'][0]
              as Map<String, dynamic>,
        );
        final meterEventSummary2 = StripeMeterEventSummary.fromJson(
          // Ignoring dynamic call for testing purposes.
          // ignore: avoid_dynamic_calls
          meterEventSummariesWithNoMorePagesJson['data'][0]
              as Map<String, dynamic>,
        );

        final result = await stripeApi.getMeterEventSummaries(
          meterId: meterId,
          customerId: customerId,
          startTimestamp: startTimestamp,
          endTimestamp: endTimestamp,
        );

        expect(result, hasLength(2));
        expect(result[0].toJson(), equals(meterEventSummary1.toJson()));
        expect(result[1].toJson(), equals(meterEventSummary2.toJson()));
      });

      group('when response has non-success status code', () {
        setUp(() {
          when(
            () => httpClient.get(any(), headers: any(named: 'headers')),
          ).thenAnswer(
            (_) async => http.Response('Not found', HttpStatus.notFound),
          );
        });

        test('throws exception', () async {
          await expectLater(
            () => stripeApi.getMeterEventSummaries(
              meterId: meterId,
              customerId: customerId,
              startTimestamp: startTimestamp,
              endTimestamp: endTimestamp,
            ),
            throwsException,
          );
        });
      });
    });
  });
}
