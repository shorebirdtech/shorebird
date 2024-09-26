import 'package:json_annotation/json_annotation.dart';
import 'package:meta/meta.dart';

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
    required this.jwtIssuer,
    this.hasActiveSubscription = false,
    this.displayName,
    this.stripeCustomerId,
    this.patchOverageLimit,
  });

  /// Converts a Map<String, dynamic> to a [User]
  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);

  // coverage:ignore-start
  /// Constructs a user with arbitrary default values for testing.
  @visibleForTesting
  factory User.forTest({
    int id = 42,
    String email = 'test@shorebird.dev',
    String jwtIssuer = 'https://accounts.google.com',
    bool hasActiveSubscription = false,
    String? displayName,
    String? stripeCustomerId,
    int? patchOverageLimit = 0,
  }) =>
      User(
        id: id,
        email: email,
        jwtIssuer: jwtIssuer,
        hasActiveSubscription: hasActiveSubscription,
        displayName: displayName,
        stripeCustomerId: stripeCustomerId,
        patchOverageLimit: patchOverageLimit,
      );
  // coverage:ignore-end

  /// Converts a [User] to a Map<String, dynamic>
  Map<String, dynamic> toJson() => _$UserToJson(this);

  /// The unique user identifier.
  final int id;

  /// The user's email address, as provided by the user during signup.
  final String email;

  /// The user's name, as provided by the user during signup.
  final String? displayName;

  /// Whether the user is currently a paying customer.
  final bool hasActiveSubscription;

  /// The user's Stripe customer ID, if they have one.
  final String? stripeCustomerId;

  /// The JWT issuer used to create the user.
  final String jwtIssuer;

  /// The maximum number of patch installs that the user has agreed to pay for
  /// as part of a pay-as-you-go plan.
  final int? patchOverageLimit;
}
