import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/role.dart';

@immutable
class EnterpriseRemovedAccessOrganizationsInner {
  const EnterpriseRemovedAccessOrganizationsInner({
    required this.organizationId,
    required this.organizationName,
    required this.role,
  });

  /// Converts a `Map<String, dynamic>` to an
  /// [EnterpriseRemovedAccessOrganizationsInner].
  factory EnterpriseRemovedAccessOrganizationsInner.fromJson(
    Map<String, dynamic> json,
  ) {
    return parseFromJson(
      'EnterpriseRemovedAccessOrganizationsInner',
      json,
      () => EnterpriseRemovedAccessOrganizationsInner(
        organizationId: json['organization_id'] as int,
        organizationName: json['organization_name'] as String,
        role: Role.fromJson(json['role'] as String),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static EnterpriseRemovedAccessOrganizationsInner? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return EnterpriseRemovedAccessOrganizationsInner.fromJson(json);
  }

  final int organizationId;
  final String organizationName;

  /// A role that a user can have relative to an Organization or App.
  final Role role;

  /// Converts an [EnterpriseRemovedAccessOrganizationsInner]
  /// to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'organization_id': organizationId,
      'organization_name': organizationName,
      'role': role.toJson(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    organizationId,
    organizationName,
    role,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is EnterpriseRemovedAccessOrganizationsInner &&
        organizationId == other.organizationId &&
        organizationName == other.organizationName &&
        role == other.role;
  }
}
