import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template nav_app}
/// An app as a navigation row, with its name and icon only.
/// {@endtemplate}
@immutable
class NavApp {
  /// {@macro nav_app}
  const NavApp({
    required this.appId,
    required this.displayName,
    required this.iconUrl,
  });

  /// Converts a `Map<String, dynamic>` to a [NavApp].
  factory NavApp.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'NavApp',
      json,
      () => NavApp(
        appId: json['app_id'] as String,
        displayName: json['display_name'] as String,
        iconUrl: checkedKey(json, 'icon_url') as String?,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static NavApp? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return NavApp.fromJson(json);
  }

  /// The ID of the app.
  final String appId;

  /// The display name of the app.
  final String displayName;

  /// The path of the app's launcher icon, as in
  /// `AppMetadata.icon_url`, or null when no analyzed release has an
  /// icon.
  final String? iconUrl;

  /// Converts a [NavApp] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'app_id': appId,
      'display_name': displayName,
      'icon_url': iconUrl,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    appId,
    displayName,
    iconUrl,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NavApp &&
        appId == other.appId &&
        displayName == other.displayName &&
        iconUrl == other.iconUrl;
  }
}
