import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/role.dart';

@immutable
class EnterpriseAppGrant {
  const EnterpriseAppGrant({
    required this.appId,
    required this.role,
  });

  /// Converts a `Map<String, dynamic>` to an [EnterpriseAppGrant].
  factory EnterpriseAppGrant.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'EnterpriseAppGrant',
      json,
      () => EnterpriseAppGrant(
        appId: json['app_id'] as String,
        role: Role.fromJson(json['role'] as String),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static EnterpriseAppGrant? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return EnterpriseAppGrant.fromJson(json);
  }

  final String appId;

  /// A role that a user can have relative to an Organization or App.
  final Role role;

  /// Converts an [EnterpriseAppGrant] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'app_id': appId,
      'role': role.toJson(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    appId,
    role,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is EnterpriseAppGrant &&
        appId == other.appId &&
        role == other.role;
  }
}
