// Some OpenAPI specs flatten inline schemas into class names long
// enough that `dart format` can't keep imports and call sites under
// 80 cols as bare identifiers.
import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template private_user}
/// A fully-detailed user object, possibly including sensitive
/// information. Should only be used when querying the user's own
/// information.
/// {@endtemplate}
@immutable
class PrivateUser {
  /// {@macro private_user}
  const PrivateUser({
    required this.id,
    required this.email,
    required this.jwtIssuer,
    this.displayName,
    this.hasActiveSubscription = false,
    this.stripeCustomerId,
    this.patchOverageLimit,
  });

  /// Converts a `Map<String, dynamic>` to a [PrivateUser].
  factory PrivateUser.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'PrivateUser',
      json,
      () => PrivateUser(
        id: json['id'] as int,
        email: json['email'] as String,
        displayName: json['display_name'] as String?,
        hasActiveSubscription:
            json['has_active_subscription'] as bool? ?? false,
        stripeCustomerId: json['stripe_customer_id'] as String?,
        jwtIssuer: json['jwt_issuer'] as String,
        patchOverageLimit: json['patch_overage_limit'] as int?,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static PrivateUser? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return PrivateUser.fromJson(json);
  }

  /// The unique user identifier.
  final int id;

  /// The user's email address, as provided by the user during signup.
  final String email;

  /// The user's name, as provided by the user during signup.
  final String? displayName;

  /// Whether the user is currently a paying customer.
  final bool? hasActiveSubscription;

  /// The user's Stripe customer ID, if they have one.
  final String? stripeCustomerId;

  /// The JWT issuer used to create the user.
  final String jwtIssuer;

  /// The maximum number of patch installs the user has agreed to
  /// pay for as part of a pay-as-you-go plan.
  final int? patchOverageLimit;

  /// Converts a [PrivateUser] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'display_name': displayName,
      'has_active_subscription': hasActiveSubscription,
      'stripe_customer_id': stripeCustomerId,
      'jwt_issuer': jwtIssuer,
      'patch_overage_limit': patchOverageLimit,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    email,
    displayName,
    hasActiveSubscription,
    stripeCustomerId,
    jwtIssuer,
    patchOverageLimit,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PrivateUser &&
        id == other.id &&
        email == other.email &&
        displayName == other.displayName &&
        hasActiveSubscription == other.hasActiveSubscription &&
        stripeCustomerId == other.stripeCustomerId &&
        jwtIssuer == other.jwtIssuer &&
        patchOverageLimit == other.patchOverageLimit;
  }
}
