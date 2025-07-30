import 'package:json_annotation/json_annotation.dart';
import 'package:stripe_api/stripe_api.dart';

part 'stripe_customer.g.dart';

/// {@template stripe_customer}
/// A partial Dart representation of the Customer object from Stripe's API.
///
/// See https://stripe.com/docs/api/customers/object.
/// {@endtemplate}
@JsonSerializable(createToJson: false)
class StripeCustomer {
  /// {@macro stripe_customer}
  StripeCustomer({required this.id, this.name, this.email, this.subscriptions});

  /// Converts a `Map<String, dynamic>` to a [StripeCustomer]
  factory StripeCustomer.fromJson(Map<String, dynamic> json) =>
      _$StripeCustomerFromJson(json);

  /// The unique identifier for this customer.
  final String id;

  /// The customer’s full name or business name.
  final String? name;

  /// The email address associated with this customer.
  final String? email;

  /// The customer’s current subscriptions, if any.
  @JsonKey(fromJson: _subscriptionsFromJson)
  final List<StripeSubscription>? subscriptions;

  @override
  String toString() => '$name - $email (id:$id)';
}

List<StripeSubscription>? _subscriptionsFromJson(Map<String, dynamic>? json) {
  final data = json?['data'] as List?;
  if (data == null) {
    return null;
  }

  return data
      .whereType<Map<String, dynamic>>()
      .map(StripeSubscription.fromJson)
      .toList();
}
