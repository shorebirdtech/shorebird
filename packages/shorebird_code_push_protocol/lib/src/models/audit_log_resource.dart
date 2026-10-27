import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template audit_log_resource}
/// OCSF `resources[]` entry, the thing the operation acted on.
/// {@endtemplate}
@immutable
class AuditLogResource {
  /// {@macro audit_log_resource}
  const AuditLogResource({
    required this.type,
    required this.uid,
  });

  /// Converts a `Map<String, dynamic>` to an [AuditLogResource].
  factory AuditLogResource.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'AuditLogResource',
      json,
      () => AuditLogResource(
        type: json['type'] as String,
        uid: json['uid'] as String,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static AuditLogResource? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return AuditLogResource.fromJson(json);
  }

  /// What `uid` identifies, such as `organization` or `release`.
  final String type;

  /// The resource's ID.
  final String uid;

  /// Converts an [AuditLogResource] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'uid': uid,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    type,
    uid,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AuditLogResource && type == other.type && uid == other.uid;
  }
}
