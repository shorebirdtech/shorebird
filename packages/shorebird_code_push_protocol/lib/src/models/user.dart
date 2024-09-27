import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

part 'user.g.dart';

/// {@template user}
/// A Shorebird user. This is a pared down version of [FullUser].
/// {@endtemplate}
@JsonSerializable()
class User {
  /// {@macro user}
  User({
    required this.id,
    required this.email,
    required this.displayName,
  });

  /// Converts a Map<String, dynamic> to a [User]
  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);

  /// Constructs a [User] from a [FullUser], removing sensitive information.
  factory User.fromFullUser(FullUser fullUser) {
    return User(
      id: fullUser.id,
      email: fullUser.email,
      displayName: fullUser.displayName,
    );
  }

  /// Converts a [User] to a JSON map.
  Map<String, dynamic> toJson() => _$UserToJson(this);

  /// The user's unique identifier.
  final int id;

  /// The user's email address.
  final String email;

  /// The user's name.
  final String? displayName;
}
