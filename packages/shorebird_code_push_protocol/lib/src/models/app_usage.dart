import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template app_usage}
/// Patch installs of one app this allotment period.
/// {@endtemplate}
@immutable
class AppUsage {
  /// {@macro app_usage}
  const AppUsage({
    required this.id,
    required this.name,
    required this.patchInstallCount,
  });

  /// Converts a `Map<String, dynamic>` to an [AppUsage].
  factory AppUsage.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'AppUsage',
      json,
      () => AppUsage(
        id: json['id'] as String,
        name: json['name'] as String,
        patchInstallCount: json['patch_install_count'] as int,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static AppUsage? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return AppUsage.fromJson(json);
  }

  /// The ID of the app.
  final String id;

  /// The display name of the app.
  final String name;

  /// The app's patch installs this allotment period.
  final int patchInstallCount;

  /// Converts an [AppUsage] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'patch_install_count': patchInstallCount,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    name,
    patchInstallCount,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AppUsage &&
        id == other.id &&
        name == other.name &&
        patchInstallCount == other.patchInstallCount;
  }
}
