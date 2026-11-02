import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template audit_log_product}
/// OCSF `metadata.product`. Always Shorebird.
/// {@endtemplate}
@immutable
class AuditLogProduct {
  /// {@macro audit_log_product}
  const AuditLogProduct({
    required this.name,
    required this.vendorName,
  });

  /// Converts a `Map<String, dynamic>` to an [AuditLogProduct].
  factory AuditLogProduct.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'AuditLogProduct',
      json,
      () => AuditLogProduct(
        name: json['name'] as String,
        vendorName: json['vendor_name'] as String,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static AuditLogProduct? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return AuditLogProduct.fromJson(json);
  }

  /// Always `Shorebird`.
  final String name;

  /// Always `Shorebird`.
  final String vendorName;

  /// Converts an [AuditLogProduct] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'vendor_name': vendorName,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    name,
    vendorName,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AuditLogProduct &&
        name == other.name &&
        vendorName == other.vendorName;
  }
}
