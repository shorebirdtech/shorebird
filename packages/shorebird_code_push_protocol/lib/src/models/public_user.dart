import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

part 'public_user.g.dart';

/// {@template user}
/// A Shorebird user. This is a pared down version of [PrivateUser].
/// {@endtemplate}
@JsonSerializable()
class PublicUser {
  /// {@macro user}
  PublicUser({
    required this.id,
    required this.email,
    required this.displayName,
  });

  /// Converts a `Map<String, dynamic>` to a [PublicUser]
  factory PublicUser.fromJson(Map<String, dynamic> json) =>
      _$PublicUserFromJson(json);

  /// Constructs a [PublicUser] from a [PrivateUser], removing sensitive
  /// information.
  factory PublicUser.fromPrivateUser(PrivateUser fullUser) {
    return PublicUser(
      id: fullUser.id,
      email: fullUser.email,
      displayName: fullUser.displayName,
    );
  }

  /// Converts a [PublicUser] to a JSON map.
  Map<String, dynamic> toJson() => _$PublicUserToJson(this);

  /// The user's unique identifier.
  final int id;

  /// The user's email address.
  final String email;

  /// The user's name.
  final String? displayName;
}
