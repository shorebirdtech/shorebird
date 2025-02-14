import 'package:json_annotation/json_annotation.dart';
import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

part 'private_user.g.dart';

/// {@template user}
/// A fully-detailed user object, possibly including sensitive information.
/// This should only be used when querying the user's own information. For other
/// users, use [PublicUser].
/// {@endtemplate}
@JsonSerializable()
class PrivateUser {
  /// {@macro user}
  const PrivateUser({
    required this.id,
    required this.email,
    required this.jwtIssuer,
    this.hasActiveSubscription = false,
    this.displayName,
    this.stripeCustomerId,
    this.patchOverageLimit,
  });

  /// Converts a `Map<String, dynamic>` to a [PrivateUser]
  factory PrivateUser.fromJson(Map<String, dynamic> json) =>
      _$PrivateUserFromJson(json);

  // coverage:ignore-start
  /// Constructs a user with arbitrary default values for testing.
  @visibleForTesting
  factory PrivateUser.forTest({
    int id = 42,
    String email = 'test@shorebird.dev',
    String jwtIssuer = 'https://accounts.google.com',
    bool hasActiveSubscription = false,
    String? displayName,
    String? stripeCustomerId,
    int? patchOverageLimit = 0,
  }) => PrivateUser(
    id: id,
    email: email,
    jwtIssuer: jwtIssuer,
    hasActiveSubscription: hasActiveSubscription,
    displayName: displayName,
    stripeCustomerId: stripeCustomerId,
    patchOverageLimit: patchOverageLimit,
  );
  // coverage:ignore-end

  /// Converts a [PrivateUser] to a `Map<String, dynamic>`
  Map<String, dynamic> toJson() => _$PrivateUserToJson(this);

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
