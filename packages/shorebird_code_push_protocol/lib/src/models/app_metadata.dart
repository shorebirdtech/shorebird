import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template app_metadata}
/// A single app which contains zero or more releases.
/// {@endtemplate}
@immutable
class AppMetadata {
  /// {@macro app_metadata}
  const AppMetadata({
    required this.appId,
    required this.displayName,
    required this.createdAt,
    required this.updatedAt,
    this.latestReleaseVersion,
    this.latestPatchNumber,
  });

  /// Converts a `Map<String, dynamic>` to an [AppMetadata].
  factory AppMetadata.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'AppMetadata',
      json,
      () => AppMetadata(
        appId: json['app_id'] as String,
        displayName: json['display_name'] as String,
        latestReleaseVersion: json['latest_release_version'] as String?,
        latestPatchNumber: json['latest_patch_number'] as int?,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static AppMetadata? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return AppMetadata.fromJson(json);
  }

  /// The ID of the app.
  final String appId;

  /// The display name of the app.
  final String displayName;

  /// The latest release version of the app.
  final String? latestReleaseVersion;

  /// The latest patch number of the app.
  final int? latestPatchNumber;

  /// The date and time the app was created.
  final DateTime createdAt;

  /// The date and time the app was last updated.
  final DateTime updatedAt;

  /// Converts an [AppMetadata] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'app_id': appId,
      'display_name': displayName,
      'latest_release_version': latestReleaseVersion,
      'latest_patch_number': latestPatchNumber,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    appId,
    displayName,
    latestReleaseVersion,
    latestPatchNumber,
    createdAt,
    updatedAt,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AppMetadata &&
        appId == other.appId &&
        displayName == other.displayName &&
        latestReleaseVersion == other.latestReleaseVersion &&
        latestPatchNumber == other.latestPatchNumber &&
        createdAt == other.createdAt &&
        updatedAt == other.updatedAt;
  }
}
