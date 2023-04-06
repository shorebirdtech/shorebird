import 'package:json_annotation/json_annotation.dart';

part 'user.g.dart';

/// {@template user}
/// A user account which contains zero or more apps.
/// {@endtemplate}
@JsonSerializable()
class User {
  /// {@macro user}
  const User({required this.id, this.hasActiveSubscription = false});

  /// Converts a Map<String, dynamic> to a [User]
  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);

  /// Converts a [User] to a Map<String, dynamic>
  Map<String, dynamic> toJson() => _$UserToJson(this);

  /// The unique user identifier.
  final int id;

  /// Whether the user has an active subscription.
  final bool hasActiveSubscription;
}
