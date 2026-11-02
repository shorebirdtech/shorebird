import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/role.dart';

@immutable
class EnterpriseRemovedAccessAppGrantsInner {
  const EnterpriseRemovedAccessAppGrantsInner({
    required this.appId,
    required this.organizationId,
    required this.role,
  });

  /// Converts a `Map<String, dynamic>` to an
  /// [EnterpriseRemovedAccessAppGrantsInner].
  factory EnterpriseRemovedAccessAppGrantsInner.fromJson(
    Map<String, dynamic> json,
  ) {
    return parseFromJson(
      'EnterpriseRemovedAccessAppGrantsInner',
      json,
      () => EnterpriseRemovedAccessAppGrantsInner(
        appId: json['app_id'] as String,
        organizationId: json['organization_id'] as int,
        role: Role.fromJson(json['role'] as String),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static EnterpriseRemovedAccessAppGrantsInner? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return EnterpriseRemovedAccessAppGrantsInner.fromJson(json);
  }

  final String appId;
  final int organizationId;

  /// A role that a user can have relative to an Organization or App.
  final Role role;

  /// Converts an [EnterpriseRemovedAccessAppGrantsInner]
  /// to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'app_id': appId,
      'organization_id': organizationId,
      'role': role.toJson(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    appId,
    organizationId,
    role,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is EnterpriseRemovedAccessAppGrantsInner &&
        appId == other.appId &&
        organizationId == other.organizationId &&
        role == other.role;
  }
}
