// Some OpenAPI specs flatten inline schemas into class names long
// enough that `dart format` can't keep imports and call sites under
// 80 cols as bare identifiers.
import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/organization.dart';
import 'package:shorebird_code_push_protocol/src/models/role.dart';

/// {@template organization_membership}
/// An organization and the current user's role in it.
/// {@endtemplate}
@immutable
class OrganizationMembership {
  /// {@macro organization_membership}
  const OrganizationMembership({
    required this.organization,
    required this.role,
  });

  /// Converts a `Map<String, dynamic>` to an [OrganizationMembership].
  factory OrganizationMembership.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'OrganizationMembership',
      json,
      () => OrganizationMembership(
        organization: Organization.fromJson(
          json['organization'] as Map<String, dynamic>,
        ),
        role: Role.fromJson(json['role'] as String),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static OrganizationMembership? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return OrganizationMembership.fromJson(json);
  }

  /// An organization groups users and apps together. Organizations
  /// can be personal (single-user) or team (multi-user).
  final Organization organization;

  /// A role that a user can have relative to an Organization or App.
  final Role role;

  /// Converts an [OrganizationMembership] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'organization': organization.toJson(),
      'role': role.toJson(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    organization,
    role,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is OrganizationMembership &&
        organization == other.organization &&
        role == other.role;
  }
}
