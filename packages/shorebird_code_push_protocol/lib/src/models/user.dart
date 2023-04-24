import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/src/models/subscription.dart';

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
    this.displayName,
  });

  /// Converts a Map<String, dynamic> to a [User]
  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);

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
}
