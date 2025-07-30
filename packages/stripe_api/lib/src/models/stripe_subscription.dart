import 'package:collection/collection.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:stripe_api/src/converters/converters.dart';
import 'package:stripe_api/stripe_api.dart';

part 'stripe_subscription.g.dart';

/// Possible states of a [StripeSubscription].
///
/// See https://stripe.com/docs/api/subscriptions/object#subscription_object-status.
enum StripeSubscriptionStatus {
  /// Subscription is active and in good standing.
  active,

  /// Subscription is unpaid and overdue.
  @JsonValue('past_due')
  pastDue,

  /// Subscription is unpaid -- no subsequent invoices will be attempted.
  unpaid,

  /// Subscription is canceled and will not renew.
  canceled,

  /// Subscription is incomplete if the initial payment attempt fails.
  incomplete,

  /// Subscription is incomplete and has expired.
  @JsonValue('incomplete_expired')
  incompleteExpired,

  /// Subscription is on trial.
  trialing,

  /// Subscription is paused.
  paused,
}

/// {@template stripe_subscription}
/// A partial Dart representation of the Subscription object from Stripe's API.
///
/// See https://stripe.com/docs/api/subscriptions/object.
/// {@endtemplate}
@JsonSerializable(createToJson: false)
class StripeSubscription {
  /// {@macro stripe_subscription}
  StripeSubscription({
    required this.id,
    required this.cancelAtPeriodEnd,
    required this.currentPeriodEnd,
    required this.currentPeriodStart,
    required this.customer,
    required this.startDate,
    required this.status,
    required this.items,
    this.endedAt,
    this.canceledAt,
    this.trialStart,
    this.trialEnd,
  });

  /// Converts a `Map<String, dynamic>` to a [StripeSubscription].
  factory StripeSubscription.fromJson(Map<String, dynamic> json) =>
      _$StripeSubscriptionFromJson(json);

  /// Unique identifier for the object.
  final String id;

  /// If the subscription has been canceled with the at_period_end flag set to
  /// true, cancel_at_period_end on the subscription will be true. You can use
  /// this attribute to determine whether a subscription that has a status of
  /// active is scheduled to be canceled at the end of the current period.
  final bool cancelAtPeriodEnd;

  /// If the subscription has been canceled, the date of that cancellation. If
  /// the subscription was canceled with cancel_at_period_end, canceled_at will
  /// reflect the time of the most recent update request, not the end of the
  /// subscription period when the subscription is automatically moved to a
  /// canceled state.
  @TimestampConverter()
  final DateTime? canceledAt;

  /// End of the current period that the subscription has been invoiced for. At
  /// the end of this period, a new invoice will be created.
  @TimestampConverter()
  final DateTime currentPeriodEnd;

  /// Start of the current period that the subscription has been invoiced for.
  @TimestampConverter()
  final DateTime currentPeriodStart;

  /// ID of the customer who owns the subscription.
  final String customer;

  /// If the subscription has ended, the date the subscription ended.
  @TimestampConverter()
  final DateTime? endedAt;

  /// Date when the subscription was first created. The date might differ from
  /// the created date due to backdating.
  @TimestampConverter()
  final DateTime startDate;

  /// Start of the trial period if this is a trial subscription.
  @TimestampConverter()
  final DateTime? trialStart;

  /// End of the trial period if this is a trial subscription.
  @TimestampConverter()
  final DateTime? trialEnd;

  /// The current state of this subscription.
  ///
  /// See https://stripe.com/docs/api/subscriptions/object#subscription_object-status.
  final StripeSubscriptionStatus status;

  /// List of subscription items, each with an attached price.
  @JsonKey(fromJson: _subscriptionItemsFromJson)
  final List<StripeSubscriptionItem> items;

  /// Whether this subscription is in an active or trialing state.
  bool get isActiveOrTrial =>
      status == StripeSubscriptionStatus.active ||
      status == StripeSubscriptionStatus.trialing;

  /// Sum of all the subscription items' prices in cents.
  int get totalCost =>
      items.map((item) => item.price.unitAmount).whereType<int>().sum;

  /// Whether this subscription contains a the pay-as-you-go product as a line
  /// item. We could also check the `usage_type` of the Stripe plan object, but
  /// this works for now.
  bool get hasMeteredBilling =>
      items.any((item) => item.price.usageType == UsageType.metered);
}

List<StripeSubscriptionItem> _subscriptionItemsFromJson(
  Map<String, dynamic>? json,
) {
  final data = json?['data'] as List? ?? [];
  return data
      .whereType<Map<String, dynamic>>()
      .map(StripeSubscriptionItem.fromJson)
      .toList();
}
