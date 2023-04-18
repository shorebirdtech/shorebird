import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

part 'stripe_event.g.dart';

/// {@template stripe_event}
/// The contents of a Stripe webhook event.
///
/// See https://stripe.com/docs/webhooks/stripe-events#event-object-structure.
/// {@endtemplate}
@JsonSerializable(createToJson: false)
class StripeEvent<T> {
  /// {@macro stripe_event}
  StripeEvent({
    required this.id,
    required this.jsonData,
  }) {
    final objectJson = jsonData['object'] as Json;
    final objectType = objectJson['object'] as String;
    switch (objectType) {
      case 'checkout.session':
        object = StripeCheckoutSession.fromJson(objectJson) as T;
        break;
      case 'subscription':
        object = StripeSubscription.fromJson(objectJson) as T;
        break;
      default:
        throw Exception('Unknown Stripe object type: $objectType');
    }
  }

  /// Creates a [StripeEvent] from a JSON object.
  factory StripeEvent.fromJson(Json json) => _$StripeEventFromJson(json);

  /// The unique identifier for this event.
  final String id;

  /// The object payload of this event.
  @JsonKey(name: 'data')
  final Json jsonData;

  /// The deserialized payload of this event.
  @JsonKey(includeFromJson: false)
  late final T object;
}
