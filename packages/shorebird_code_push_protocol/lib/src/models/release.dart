// Some OpenAPI specs flatten inline schemas into class names long
// enough that `dart format` can't keep imports and call sites under
// 80 cols as bare identifiers.
import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/release_platform.dart';
import 'package:shorebird_code_push_protocol/src/models/release_status.dart';

/// {@template release}
/// A release build of an application that is distributed to devices.
/// A release can have zero or more patches applied to it.
/// {@endtemplate}
@immutable
class Release {
  /// {@macro release}
  const Release({
    required this.id,
    required this.appId,
    required this.version,
    required this.flutterRevision,
    required this.platformStatuses,
    required this.createdAt,
    required this.updatedAt,
    this.flutterVersion,
    this.displayName,
    this.notes,
  });

  /// Converts a `Map<String, dynamic>` to a [Release].
  factory Release.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'Release',
      json,
      () => Release(
        id: json['id'] as int,
        appId: json['app_id'] as String,
        version: json['version'] as String,
        flutterRevision: json['flutter_revision'] as String,
        flutterVersion: json['flutter_version'] as String?,
        displayName: json['display_name'] as String?,
        platformStatuses: (json['platform_statuses'] as Map<String, dynamic>)
            .map(
              (key, value) => MapEntry(
                ReleasePlatform.fromJson(key),
                ReleaseStatus.fromJson(value as String),
              ),
            ),
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
        notes: json['notes'] as String?,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static Release? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return Release.fromJson(json);
  }

  /// The ID of the release.
  final int id;

  /// The ID of the app.
  final String appId;

  /// The version of the release.
  final String version;

  /// The Flutter revision used to create the release.
  final String flutterRevision;

  /// The Flutter version used to create the release. Optional
  /// because it was added later; older releases do not have it.
  final String? flutterVersion;

  /// The display name for the release.
  final String? displayName;

  /// The status of the release for each platform.
  final Map<ReleasePlatform, ReleaseStatus> platformStatuses;

  /// The date and time the release was created.
  final DateTime createdAt;

  /// The date and time the release was last updated.
  final DateTime updatedAt;

  /// Freeform notes associated with the release, if any.
  final String? notes;

  /// Converts a [Release] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'app_id': appId,
      'version': version,
      'flutter_revision': flutterRevision,
      'flutter_version': flutterVersion,
      'display_name': displayName,
      'platform_statuses': platformStatuses.map(
        (key, value) => MapEntry(key.toJson(), value.toJson()),
      ),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'notes': notes,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    appId,
    version,
    flutterRevision,
    flutterVersion,
    displayName,
    mapHash(platformStatuses),
    createdAt,
    updatedAt,
    notes,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Release &&
        id == other.id &&
        appId == other.appId &&
        version == other.version &&
        flutterRevision == other.flutterRevision &&
        flutterVersion == other.flutterVersion &&
        displayName == other.displayName &&
        mapsEqual(platformStatuses, other.platformStatuses) &&
        createdAt == other.createdAt &&
        updatedAt == other.updatedAt &&
        notes == other.notes;
  }
}
