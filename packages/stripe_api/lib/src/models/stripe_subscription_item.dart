import 'package:json_annotation/json_annotation.dart';
import 'package:stripe_api/stripe_api.dart';

part 'stripe_subscription_item.g.dart';

/// {@template stripe_subscription_item}
/// A partial Dart representation of the SubscriptionItem object from Stripe's
/// API.
///
/// See https://stripe.com/docs/api/subscription_items/object.
/// {@endtemplate}
@JsonSerializable(createToJson: false)
class StripeSubscriptionItem {
  /// {@macro stripe_subscription_item}
  const StripeSubscriptionItem({
    required this.id,
    required this.price,
    this.quantity,
  });

  /// Converts a JSON object to a [StripeSubscriptionItem].
  factory StripeSubscriptionItem.fromJson(Map<String, dynamic> json) =>
      _$StripeSubscriptionItemFromJson(json);

  /// Unique identifier for the object, of the form "si_{base64_id}".
  final String id;

  /// The price the customer is subscribed to.
  final StripePrice price;

  /// The quantity of the plan to which the customer should be subscribed. This
  /// will be null if the associated plan has a `metered` usage type.
  final int? quantity;
}
