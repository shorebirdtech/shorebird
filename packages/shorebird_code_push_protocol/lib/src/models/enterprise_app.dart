import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template enterprise_app}
/// An app in one of an enterprise's organizations.
/// {@endtemplate}
@immutable
class EnterpriseApp {
  /// {@macro enterprise_app}
  const EnterpriseApp({
    required this.organizationId,
    required this.organizationName,
    required this.appId,
    required this.appDisplayName,
  });

  /// Converts a `Map<String, dynamic>` to an [EnterpriseApp].
  factory EnterpriseApp.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'EnterpriseApp',
      json,
      () => EnterpriseApp(
        organizationId: json['organization_id'] as int,
        organizationName: json['organization_name'] as String,
        appId: json['app_id'] as String,
        appDisplayName: json['app_display_name'] as String,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static EnterpriseApp? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return EnterpriseApp.fromJson(json);
  }

  final int organizationId;
  final String organizationName;
  final String appId;
  final String appDisplayName;

  /// Converts an [EnterpriseApp] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'organization_id': organizationId,
      'organization_name': organizationName,
      'app_id': appId,
      'app_display_name': appDisplayName,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    organizationId,
    organizationName,
    appId,
    appDisplayName,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is EnterpriseApp &&
        organizationId == other.organizationId &&
        organizationName == other.organizationName &&
        appId == other.appId &&
        appDisplayName == other.appDisplayName;
  }
}
