import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template audit_log_source_endpoint}
/// OCSF `src_endpoint`, where the request came from: `ip` when it was
/// recorded, otherwise `name` set to `unknown`.
/// {@endtemplate}
@immutable
class AuditLogSourceEndpoint {
  /// {@macro audit_log_source_endpoint}
  const AuditLogSourceEndpoint({
    this.ip,
    this.name,
  });

  /// Converts a `Map<String, dynamic>` to an [AuditLogSourceEndpoint].
  factory AuditLogSourceEndpoint.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'AuditLogSourceEndpoint',
      json,
      () => AuditLogSourceEndpoint(
        ip: json['ip'] as String?,
        name: json['name'] as String?,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static AuditLogSourceEndpoint? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return AuditLogSourceEndpoint.fromJson(json);
  }

  /// The client's IP address.
  final String? ip;

  /// `unknown`, when no IP address is given.
  final String? name;

  /// Converts an [AuditLogSourceEndpoint] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'ip': ?ip,
      'name': ?name,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    ip,
    name,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AuditLogSourceEndpoint &&
        ip == other.ip &&
        name == other.name;
  }
}
