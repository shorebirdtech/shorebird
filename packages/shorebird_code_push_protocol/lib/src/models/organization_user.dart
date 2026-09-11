import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/public_user.dart';
import 'package:shorebird_code_push_protocol/src/models/role.dart';

/// {@template organization_user}
/// A member of an organization and their role.
/// {@endtemplate}
@immutable
class OrganizationUser {
  /// {@macro organization_user}
  const OrganizationUser({
    required this.user,
    required this.role,
  });

  /// Converts a `Map<String, dynamic>` to an [OrganizationUser].
  factory OrganizationUser.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'OrganizationUser',
      json,
      () => OrganizationUser(
        user: PublicUser.fromJson(json['user'] as Map<String, dynamic>),
        role: Role.fromJson(json['role'] as String),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static OrganizationUser? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return OrganizationUser.fromJson(json);
  }

  /// A Shorebird user with non-sensitive information only.
  final PublicUser user;

  /// A role that a user can have relative to an Organization or App.
  final Role role;

  /// Converts an [OrganizationUser] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'user': user.toJson(),
      'role': role.toJson(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    user,
    role,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is OrganizationUser &&
        user == other.user &&
        role == other.role;
  }
}
