import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template enterprise_billing_organization}
/// An organization an enterprise's billing account pays for.
/// {@endtemplate}
@immutable
class EnterpriseBillingOrganization {
  /// {@macro enterprise_billing_organization}
  const EnterpriseBillingOrganization({
    required this.id,
    required this.name,
    required this.appCount,
    required this.patchInstalls,
  });

  /// Converts a `Map<String, dynamic>` to an [EnterpriseBillingOrganization].
  factory EnterpriseBillingOrganization.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'EnterpriseBillingOrganization',
      json,
      () => EnterpriseBillingOrganization(
        id: json['id'] as int,
        name: json['name'] as String,
        appCount: json['app_count'] as int,
        patchInstalls: json['patch_installs'] as int,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static EnterpriseBillingOrganization? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return EnterpriseBillingOrganization.fromJson(json);
  }

  final int id;
  final String name;
  final int appCount;

  /// Its apps' patch installs in the plan's current period.
  final int patchInstalls;

  /// Converts an [EnterpriseBillingOrganization] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'app_count': appCount,
      'patch_installs': patchInstalls,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    name,
    appCount,
    patchInstalls,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is EnterpriseBillingOrganization &&
        id == other.id &&
        name == other.name &&
        appCount == other.appCount &&
        patchInstalls == other.patchInstalls;
  }
}
