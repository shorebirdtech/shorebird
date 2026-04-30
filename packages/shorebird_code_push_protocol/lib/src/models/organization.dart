// Some OpenAPI specs flatten inline schemas into class names long
// enough that `dart format` can't keep imports and call sites under
// 80 cols as bare identifiers.
import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/organization_type.dart';

/// {@template organization}
/// An organization groups users and apps together. Organizations
/// can be personal (single-user) or team (multi-user).
/// {@endtemplate}
@immutable
class Organization {
  /// {@macro organization}
  const Organization({
    required this.id,
    required this.name,
    required this.organizationType,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Converts a `Map<String, dynamic>` to an [Organization].
  factory Organization.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'Organization',
      json,
      () => Organization(
        id: json['id'] as int,
        name: json['name'] as String,
        organizationType: OrganizationType.fromJson(
          json['organization_type'] as String,
        ),
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static Organization? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return Organization.fromJson(json);
  }

  /// The unique identifier for the organization.
  final int id;

  /// The name of the organization.
  final String name;

  /// Distinguishes personal organizations (single-user) from team
  /// organizations (multi-user).
  final OrganizationType organizationType;

  /// When this organization was created.
  final DateTime createdAt;

  /// When this organization was last updated.
  final DateTime updatedAt;

  /// Converts an [Organization] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'organization_type': organizationType.toJson(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    name,
    organizationType,
    createdAt,
    updatedAt,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Organization &&
        id == other.id &&
        name == other.name &&
        organizationType == other.organizationType &&
        createdAt == other.createdAt &&
        updatedAt == other.updatedAt;
  }
}
