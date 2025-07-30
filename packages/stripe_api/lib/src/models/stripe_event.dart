import 'package:json_annotation/json_annotation.dart';
import 'package:stripe_api/src/converters/converters.dart';
import 'package:stripe_api/stripe_api.dart';

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
    required this.created,
  }) {
    final objectJson = jsonData['object'] as Map<String, dynamic>;
    final objectType = objectJson['object'] as String;
    switch (objectType) {
      case 'checkout.session':
        object = StripeCheckoutSession.fromJson(objectJson) as T;
      case 'subscription':
        object = StripeSubscription.fromJson(objectJson) as T;
      default:
        throw Exception('Unknown Stripe object type: $objectType');
    }
  }

  /// Creates a [StripeEvent] from a JSON object.
  factory StripeEvent.fromJson(Map<String, dynamic> json) =>
      _$StripeEventFromJson(json);

  /// The unique identifier for this event.
  final String id;

  /// When this event was created.
  @TimestampConverter()
  final DateTime created;

  /// The object payload of this event.
  @JsonKey(name: 'data')
  final Map<String, dynamic> jsonData;

  /// The deserialized payload of this event.
  @JsonKey(includeFromJson: false)
  late final T object;
}
