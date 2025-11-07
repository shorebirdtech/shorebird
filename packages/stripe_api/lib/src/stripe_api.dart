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
      throw Exception('Failed to retrieve customer with id $customerId');
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
      throw Exception(
        'Failed to retrieve subscription with id $subscriptionId',
      );
    }

    return StripeSubscription.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
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
      throw Exception('''
Failed to report $value for customer $customerId. Error:
${response.body}
''');
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
        queryParameters: queryParameters
          ..addAll({
            // 100 is the max, as per https://docs.stripe.com/api/pagination
            'limit': '100',
            if (pagedObjects.isNotEmpty)
              'starting_after': getId(pagedObjects.last),
          }),
      );

      final response = await _client.get(uri, headers: _authHeaders);
      if (response.statusCode != HttpStatus.ok) {
        throw Exception('''
Failed to get paged response from $path with params $queryParameters. Error:
${response.body}
''');
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
