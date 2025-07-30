import 'dart:convert';
import 'dart:io';

const stripeJsonPath = 'test/fixtures/stripe/json';

String get checkoutSessionCompletedEventJsonString => File(
  '$stripeJsonPath/checkout_session_completed_event.json',
).readAsStringSync();

Map<String, dynamic> get checkoutSessionCompletedEventJson =>
    jsonDecode(checkoutSessionCompletedEventJsonString) as Map<String, dynamic>;

String get createPaymentLinkJsonString =>
    File('$stripeJsonPath/create_payment_link.json').readAsStringSync();

String get customerJsonString =>
    File('$stripeJsonPath/customer.json').readAsStringSync();

Map<String, dynamic> get customerJson =>
    jsonDecode(customerJsonString) as Map<String, dynamic>;

String get customerWithEmptySubscriptionJsonString => File(
  '$stripeJsonPath/customer_with_empty_subscriptions.json',
).readAsStringSync();

String get customerWithSubscriptionJsonString =>
    File('$stripeJsonPath/customer_with_subscription.json').readAsStringSync();

String get customerWithInactiveSubscriptionJsonString => File(
  '$stripeJsonPath/customer_with_inactive_subscription.json',
).readAsStringSync();

String get subscriptionJsonString =>
    File('$stripeJsonPath/subscription.json').readAsStringSync();

Map<String, dynamic> get subscriptionJson =>
    jsonDecode(subscriptionJsonString) as Map<String, dynamic>;

String get trialingSubscriptionString =>
    File('$stripeJsonPath/trialing_subscription.json').readAsStringSync();

Map<String, dynamic> get trialingSubscriptionJson =>
    jsonDecode(trialingSubscriptionString) as Map<String, dynamic>;

String get subscriptionWithPricingTiersJsonString => File(
  '$stripeJsonPath/subscription_with_pricing_tiers.json',
).readAsStringSync();

Map<String, dynamic> get subscriptionWithPricingTiersJson =>
    jsonDecode(subscriptionWithPricingTiersJsonString) as Map<String, dynamic>;

String get subscriptionCreatedEventJsonString =>
    File('$stripeJsonPath/subscription_created_event.json').readAsStringSync();

Map<String, dynamic> get subscriptionCreatedEventJson =>
    jsonDecode(subscriptionCreatedEventJsonString) as Map<String, dynamic>;

String get customerSearchOneResultWithExpandedSubscriptionsJsonString => File(
  '$stripeJsonPath/customer_search_one_result_with_expanded_subscriptions.json',
).readAsStringSync();

Map<String, dynamic> get customerSearchOneResultWithExpandedSubscriptionsJson =>
    jsonDecode(customerSearchOneResultWithExpandedSubscriptionsJsonString)
        as Map<String, dynamic>;

String get meterEventSummariesWithNoMorePagesJsonString => File(
  '$stripeJsonPath/meter_event_summaries_no_more_pages.json',
).readAsStringSync();

Map<String, dynamic> get meterEventSummariesWithNoMorePagesJson =>
    jsonDecode(meterEventSummariesWithNoMorePagesJsonString)
        as Map<String, dynamic>;

String get meterEventSummariesWithMorePagesJsonString => File(
  '$stripeJsonPath/meter_event_summaries_with_more_pages.json',
).readAsStringSync();

Map<String, dynamic> get meterEventSummariesWithMorePagesJson =>
    jsonDecode(meterEventSummariesWithMorePagesJsonString)
        as Map<String, dynamic>;

String get platformAccessSubscriptionItemJsonString => File(
  '$stripeJsonPath/platform_access_subscription_item.json',
).readAsStringSync();

Map<String, dynamic> get subscriptionItemJson =>
    jsonDecode(platformAccessSubscriptionItemJsonString)
        as Map<String, dynamic>;

String get payAsYouGoSubscriptionItemJsonString => File(
  '$stripeJsonPath/pay_as_you_go_subscription_item.json',
).readAsStringSync();

Map<String, dynamic> get payAsYouGoSubscriptionItemJson =>
    jsonDecode(payAsYouGoSubscriptionItemJsonString) as Map<String, dynamic>;
