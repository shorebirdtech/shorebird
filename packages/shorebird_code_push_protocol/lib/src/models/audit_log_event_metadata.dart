import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/audit_log_product.dart';

/// {@template audit_log_event_metadata}
/// OCSF `metadata` for an audit log entry.
/// {@endtemplate}
@immutable
class AuditLogEventMetadata {
  /// {@macro audit_log_event_metadata}
  const AuditLogEventMetadata({
    required this.version,
    required this.product,
    required this.uid,
    required this.tenantUid,
    this.correlationUid,
  });

  /// Converts a `Map<String, dynamic>` to an [AuditLogEventMetadata].
  factory AuditLogEventMetadata.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'AuditLogEventMetadata',
      json,
      () => AuditLogEventMetadata(
        version: json['version'] as String,
        product: AuditLogProduct.fromJson(
          json['product'] as Map<String, dynamic>,
        ),
        uid: json['uid'] as String,
        tenantUid: json['tenant_uid'] as String,
        correlationUid: json['correlation_uid'] as String?,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static AuditLogEventMetadata? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return AuditLogEventMetadata.fromJson(json);
  }

  /// The OCSF schema version, `1.9.0`.
  final String version;

  /// OCSF `metadata.product`. Always Shorebird.
  final AuditLogProduct product;

  /// The entry's ID, as a string.
  final String uid;

  /// The organization's ID, as a string.
  final String tenantUid;

  /// Always `audit`.
  String get logName => 'audit';

  /// The ID of the request that caused the entry, when recorded.
  /// Quote it to Shorebird support to trace the request.
  final String? correlationUid;

  /// Converts an [AuditLogEventMetadata] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'product': product.toJson(),
      'uid': uid,
      'tenant_uid': tenantUid,
      'log_name': logName,
      'correlation_uid': ?correlationUid,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    version,
    product,
    uid,
    tenantUid,
    correlationUid,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AuditLogEventMetadata &&
        version == other.version &&
        product == other.product &&
        uid == other.uid &&
        tenantUid == other.tenantUid &&
        correlationUid == other.correlationUid;
  }
}
