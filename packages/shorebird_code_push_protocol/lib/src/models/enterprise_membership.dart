import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/enterprise_role.dart';

/// {@template enterprise_membership}
/// An enterprise the caller belongs to, and their role in it.
/// {@endtemplate}
@immutable
class EnterpriseMembership {
  /// {@macro enterprise_membership}
  const EnterpriseMembership({
    required this.id,
    required this.name,
    required this.role,
  });

  /// Converts a `Map<String, dynamic>` to an [EnterpriseMembership].
  factory EnterpriseMembership.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'EnterpriseMembership',
      json,
      () => EnterpriseMembership(
        id: json['id'] as int,
        name: json['name'] as String,
        role: EnterpriseRole.fromJson(json['role'] as String),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static EnterpriseMembership? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return EnterpriseMembership.fromJson(json);
  }

  final int id;
  final String name;

  /// A person's role in an enterprise.
  final EnterpriseRole role;

  /// Converts an [EnterpriseMembership] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'role': role.toJson(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    name,
    role,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is EnterpriseMembership &&
        id == other.id &&
        name == other.name &&
        role == other.role;
  }
}
