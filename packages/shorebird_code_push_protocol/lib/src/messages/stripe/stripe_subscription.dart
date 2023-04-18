import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:shorebird_code_push_protocol/src/converters/converters.dart';

part 'stripe_subscription.g.dart';

/// Possible states of a [StripeSubscription].
///
/// See https://stripe.com/docs/api/subscriptions/object#subscription_object-status.
enum StripeSubscriptionStatus {
  // ignore: public_member_api_docs
  active,
  @JsonValue('past_due')
  // ignore: public_member_api_docs
  pastDue,
  // ignore: public_member_api_docs
  unpaid,
  // ignore: public_member_api_docs
  canceled,
  // ignore: public_member_api_docs
  incomplete,
  @JsonValue('incomplete_expired')
  // ignore: public_member_api_docs
  incompleteExpired,
  // ignore: public_member_api_docs
  trialing,
  // ignore: public_member_api_docs
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
    this.endedAt,
    this.canceledAt,
  });

  /// Converts a Map<String, dynamic> to a [StripeSubscription].
  factory StripeSubscription.fromJson(Json json) =>
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

  /// The current state of this subscription.
  ///
  /// See https://stripe.com/docs/api/subscriptions/object#subscription_object-status.
  final StripeSubscriptionStatus status;
}
