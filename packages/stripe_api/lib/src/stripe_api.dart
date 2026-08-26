import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:stripe_api/src/models/internal/internal.dart';
import 'package:stripe_api/stripe_api.dart';

/// {@template stripe_api}
/// Allows interaction with the Stripe API.
/// {@endtemplate}
class StripeApi {
  /// {@macro stripe_api}
  StripeApi({required String secretKey, http.Client? client})
    : _client = client ?? http.Client(),
      _secretKey = secretKey;

  final http.Client _client;
  final String _secretKey;

  /// Fetches all active and trial subscriptions for [customerId].
  Future<List<StripeSubscription>> fetchActiveOrTrialSubscriptions({
    required String customerId,
  }) async {
    final customer = await fetchCustomer(customerId: customerId);
    return (customer.subscriptions ?? [])
        .where((subscription) => subscription.isActiveOrTrial)
        .toList();
  }

  /// Retrieves a [StripeCustomer] with the given [customerId].
  Future<StripeCustomer> fetchCustomer({required String customerId}) async {
    final uri = _stripeUri(
      path: 'customers/$customerId',
      queryParameters: {'expand[]': 'subscriptions'},
    );

    final response = await _client.get(uri, headers: _authHeaders);
    if (response.statusCode != HttpStatus.ok) {
      throw StripeApiException.fromResponse(
        response,
        message: 'Failed to retrieve customer with id $customerId',
      );
    }

    return StripeCustomer.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Retrieves a [StripeSubscription] with the given [subscriptionId].
  Future<StripeSubscription> fetchSubscription({
    required String subscriptionId,
  }) async {
    final uri = _stripeUri(
      path: 'subscriptions/$subscriptionId',
      queryParameters: {'expand[]': 'items.data.price.tiers'},
    );

    final response = await _client.get(uri, headers: _authHeaders);
    if (response.statusCode != HttpStatus.ok) {
      throw StripeApiException.fromResponse(
        response,
        message: 'Failed to retrieve subscription with id $subscriptionId',
      );
    }

    return StripeSubscription.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Retrieves a [StripePaymentMethod] with the given [paymentMethodId].
  ///
  /// See https://docs.stripe.com/api/payment_methods/retrieve.
  Future<StripePaymentMethod> fetchPaymentMethod({
    required String paymentMethodId,
  }) async {
    final uri = _stripeUri(path: 'payment_methods/$paymentMethodId');

    final response = await _client.get(uri, headers: _authHeaders);
    if (response.statusCode != HttpStatus.ok) {
      throw StripeApiException.fromResponse(
        response,
        message: 'Failed to retrieve payment method with id $paymentMethodId',
      );
    }

    return StripePaymentMethod.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Lists every subscription belonging to [customerId] that has not been
  /// canceled, regardless of status.
  ///
  /// Prices are not expanded, so [StripePrice.tiers] is null on the returned
  /// subscriptions. Use [fetchSubscription] when tiers are needed.
  Future<List<StripeSubscription>> listSubscriptions({
    required String customerId,
  }) => _fetchAllPages(
    path: 'subscriptions',
    queryParameters: {'customer': customerId},
    fromJson: StripeSubscription.fromJson,
    getId: (e) => e.id,
  );

  /// Creates a subscription for [customerId] on [priceId].
  ///
  /// [idempotencyKey] must be unique per logical creation attempt: Stripe
  /// replays the original response for a reused key for ~24 hours, so a key
  /// derived from stable identity would return an earlier subscription instead
  /// of creating one.
  ///
  /// A null [currency] or [defaultPaymentMethod] is omitted from the request
  /// rather than sent empty, which leaves Stripe to fall back to the
  /// customer's own currency and default payment method.
  ///
  /// [collectionMethod] selects how invoices collect: null leaves Stripe's
  /// default (`charge_automatically`); `send_invoice` emails a hosted invoice
  /// instead of charging the payment method, and Stripe then requires
  /// [daysUntilDue].
  ///
  /// See https://docs.stripe.com/api/subscriptions/create.
  Future<StripeSubscription> createSubscription({
    required String customerId,
    required String priceId,
    required bool automaticTaxEnabled,
    required Map<String, String> metadata,
    required String idempotencyKey,
    String? currency,
    String? defaultPaymentMethod,
    String? collectionMethod,
    int? daysUntilDue,
  }) async {
    final uri = _stripeUri(path: 'subscriptions');
    final response = await _client.post(
      uri,
      headers: {..._authHeaders, 'Idempotency-Key': idempotencyKey},
      body: {
        'customer': customerId,
        'items[0][price]': priceId,
        'currency': ?currency,
        'default_payment_method': ?defaultPaymentMethod,
        'collection_method': ?collectionMethod,
        'days_until_due': ?daysUntilDue?.toString(),
        'automatic_tax[enabled]': '$automaticTaxEnabled',
        for (final entry in metadata.entries)
          'metadata[${entry.key}]': entry.value,
      },
    );

    if (response.statusCode != HttpStatus.ok) {
      throw StripeApiException.fromResponse(
        response,
        message:
            'Failed to create subscription on $priceId for customer '
            '$customerId',
      );
    }

    return StripeSubscription.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Immediately cancels the subscription with the given [subscriptionId].
  ///
  /// [invoiceNow] and [prorate] control whether pending metered usage is
  /// invoiced on cancellation; Stripe does neither by default.
  ///
  /// See https://docs.stripe.com/api/subscriptions/cancel.
  Future<void> cancelSubscription({
    required String subscriptionId,
    required bool invoiceNow,
    required bool prorate,
  }) async {
    final uri = _stripeUri(path: 'subscriptions/$subscriptionId');
    final response = await _client.delete(
      uri,
      headers: _authHeaders,
      body: {'invoice_now': '$invoiceNow', 'prorate': '$prorate'},
    );

    if (response.statusCode != HttpStatus.ok) {
      throw StripeApiException.fromResponse(
        response,
        message: 'Failed to cancel subscription with id $subscriptionId',
      );
    }
  }

  /// Retrieves all [StripeBillingMeter]s associated with the Stripe account.
  Future<List<StripeBillingMeter>> fetchActiveBillingMeters() async {
    return _fetchAllPages(
      path: 'billing/meters',
      queryParameters: {'status': 'active'},
      fromJson: StripeBillingMeter.fromJson,
      getId: (e) => e.id,
    );
  }

  /// Creates a new meter event for the given [customerId].
  /// See https://docs.stripe.com/api/billing/meter-event
  Future<void> createMeterEvent({
    required String customerId,
    required String eventName,
    required int value,
    int? timestamp,
  }) async {
    final uri = _stripeUri(path: 'billing/meter_events');
    final response = await _client.post(
      uri,
      headers: _authHeaders,
      body: {
        'event_name': eventName,
        'payload[value]': '$value',
        'payload[stripe_customer_id]': customerId,
        if (timestamp != null) 'timestamp': '$timestamp',
      },
    );

    if (response.statusCode != HttpStatus.ok) {
      throw StripeApiException.fromResponse(
        response,
        message:
            '''
Failed to report $value for customer $customerId. Error:
${response.body}
''',
      );
    }
  }

  /// Fetches all meter event summaries for the given [meterId] and [customerId]
  /// within the given [startTimestamp] and [endTimestamp].
  Future<List<StripeMeterEventSummary>> getMeterEventSummaries({
    required String meterId,
    required String customerId,
    required int startTimestamp,
    required int endTimestamp,
  }) async {
    return _fetchAllPages(
      path: 'billing/meters/$meterId/event_summaries',
      queryParameters: {
        'customer': customerId,
        'start_time': '$startTimestamp',
        'end_time': '$endTimestamp',
      },
      fromJson: StripeMeterEventSummary.fromJson,
      getId: (e) => e.id,
    );
  }

  /// Fetches all pages of objects from a paginated endpoint.
  Future<List<T>> _fetchAllPages<T>({
    required String path,
    required T Function(Map<String, dynamic>) fromJson,
    required String Function(T) getId,
    Map<String, String> queryParameters = const {},
  }) async {
    final pagedObjects = <T>[];

    while (true) {
      final uri = _stripeUri(
        path: path,
        queryParameters: {
          ...queryParameters,
          // 100 is the max, as per https://docs.stripe.com/api/pagination
          'limit': '100',
          if (pagedObjects.isNotEmpty)
            'starting_after': getId(pagedObjects.last),
        },
      );

      final response = await _client.get(uri, headers: _authHeaders);
      if (response.statusCode != HttpStatus.ok) {
        throw StripeApiException.fromResponse(
          response,
          message:
              '''
Failed to get paged response from $path with params $queryParameters. Error:
${response.body}
''',
        );
      }

      final pagedResponse = PagedResponse.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );

      pagedObjects.addAll(
        pagedResponse.data.whereType<Map<String, dynamic>>().map(fromJson),
      );

      if (!pagedResponse.hasMore) {
        break;
      }
    }

    return pagedObjects;
  }

  late final Map<String, String> _authHeaders = {
    HttpHeaders.authorizationHeader: 'Bearer $_secretKey',
  };

  Uri _stripeUri({
    required String path,
    Map<String, String>? queryParameters,
  }) => Uri(
    scheme: 'https',
    host: 'api.stripe.com',
    path: '/v1/$path',
    queryParameters: queryParameters,
  );
}
