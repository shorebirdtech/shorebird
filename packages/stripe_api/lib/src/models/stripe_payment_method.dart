import 'package:json_annotation/json_annotation.dart';

part 'stripe_payment_method.g.dart';

/// {@template stripe_payment_method}
/// A payment method in Stripe.
///
/// Only the fields needed to pick a collection method are modeled. [card] is
/// null for non-card payment methods.
///
/// See https://docs.stripe.com/api/payment_methods/object
/// {@endtemplate}
@JsonSerializable(createToJson: false)
class StripePaymentMethod {
  /// {@macro stripe_payment_method}
  const StripePaymentMethod({required this.id, this.card});

  /// Converts a JSON object to a [StripePaymentMethod].
  factory StripePaymentMethod.fromJson(Map<String, dynamic> json) =>
      _$StripePaymentMethodFromJson(json);

  /// The unique identifier for this object.
  final String id;

  /// Card details, when this payment method is a card.
  final StripePaymentMethodCard? card;
}

/// {@template stripe_payment_method_card}
/// Card details on a [StripePaymentMethod].
/// {@endtemplate}
@JsonSerializable(createToJson: false)
class StripePaymentMethodCard {
  /// {@macro stripe_payment_method_card}
  const StripePaymentMethodCard({this.country});

  /// Converts a JSON object to a [StripePaymentMethodCard].
  factory StripePaymentMethodCard.fromJson(Map<String, dynamic> json) =>
      _$StripePaymentMethodCardFromJson(json);

  /// Two-letter ISO country code of the issuing bank, e.g. `IN`.
  final String? country;
}
