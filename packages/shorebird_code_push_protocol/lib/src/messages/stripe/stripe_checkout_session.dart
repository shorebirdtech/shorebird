import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

part 'stripe_checkout_session.g.dart';

/// {@template stripe_checkout_session}
/// A Checkout Session represents your customer's session as they pay for
/// one-time purchases or subscriptions through Checkout or Payment Links.
///
/// See https://stripe.com/docs/api/checkout/sessions/object.
/// {@endtemplate}
@JsonSerializable(createToJson: false)
class StripeCheckoutSession {
  /// {@macro stripe_checkout_session}
  StripeCheckoutSession({
    required this.customerId,
    required this.metadata,
  });

  /// Creates a [StripeCheckoutSession] from a JSON object.
  factory StripeCheckoutSession.fromJson(Json json) =>
      _$StripeCheckoutSessionFromJson(json);

  /// The Stripe customer ID associated with this [StripeCheckoutSession].
  @JsonKey(name: 'customer')
  final String customerId;

  /// Extra data associated with this [StripeCheckoutSession].
  ///
  /// We use this to store the email address of the customer using the
  /// "shorebird_email" key.
  final Json metadata;
}
