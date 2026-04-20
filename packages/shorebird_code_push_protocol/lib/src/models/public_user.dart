import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template public_user}
/// A Shorebird user with non-sensitive information only.
/// {@endtemplate}
@immutable
class PublicUser {
  /// {@macro public_user}
  const PublicUser({
    required this.id,
    required this.email,
    this.displayName,
  });

  /// Converts a `Map<String, dynamic>` to a [PublicUser].
  factory PublicUser.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'PublicUser',
      json,
      () => PublicUser(
        id: json['id'] as int,
        email: json['email'] as String,
        displayName: json['display_name'] as String?,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static PublicUser? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return PublicUser.fromJson(json);
  }

  /// The user's unique identifier.
  final int id;

  /// The user's email address.
  final String email;

  /// The user's name.
  final String? displayName;

  /// Converts a [PublicUser] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'display_name': displayName,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    email,
    displayName,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PublicUser &&
        id == other.id &&
        email == other.email &&
        displayName == other.displayName;
  }
}
