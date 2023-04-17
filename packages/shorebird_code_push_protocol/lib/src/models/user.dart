import 'package:json_annotation/json_annotation.dart';

part 'user.g.dart';

/// {@template user}
/// A user account which contains zero or more apps.
/// {@endtemplate}
@JsonSerializable()
class User {
  /// {@macro user}
  const User({
    required this.id,
    required this.email,
    this.hasActiveSubscription = false,
    this.stripeCustomerId,
  });

  /// Converts a Map<String, dynamic> to a [User]
  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);

  /// Converts a [User] to a Map<String, dynamic>
  Map<String, dynamic> toJson() => _$UserToJson(this);

  /// The unique user identifier.
  final int id;

  /// The user's email address, as provided by the user during signup.
  final String email;

  /// Whether the user is currently a paying customer.
  final bool hasActiveSubscription;

  /// The user's Stripe customer id.
  ///
  /// This will be null for users that have never paid.
  final String? stripeCustomerId;
}
