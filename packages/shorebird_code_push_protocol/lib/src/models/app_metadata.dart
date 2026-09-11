import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/latest_release.dart';
import 'package:shorebird_code_push_protocol/src/models/pending_release.dart';
import 'package:shorebird_code_push_protocol/src/models/release_platform.dart';

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
    this.platforms,
    this.latestReleases,
    this.pendingReleases,
    this.iconUrl,
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
        platforms: (json['platforms'] as List?)
            ?.map<ReleasePlatform>((e) => ReleasePlatform.fromJson(e as String))
            .toList(),
        latestReleases: (json['latest_releases'] as Map<String, dynamic>?)?.map(
          (key, value) => MapEntry(
            ReleasePlatform.fromJson(key),
            LatestRelease.fromJson(value as Map<String, dynamic>),
          ),
        ),
        pendingReleases: (json['pending_releases'] as Map<String, dynamic>?)
            ?.map(
              (key, value) => MapEntry(
                ReleasePlatform.fromJson(key),
                PendingRelease.fromJson(value as Map<String, dynamic>),
              ),
            ),
        iconUrl: json['icon_url'] as String?,
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

  /// Every platform the app has shipped to (i.e. has at least one
  /// release artifact for). Independent of `latest_releases`:
  /// an app can list a platform here even if no release on that
  /// platform has been analyzed yet.
  final List<ReleasePlatform>? platforms;

  /// The latest analyzed release per platform. A platform is
  /// omitted when no release for that platform has been analyzed
  /// yet. When the latest release for a platform is not yet
  /// analyzed but a previous one is, the previous release is
  /// returned here and `pending_releases.{platform}` identifies
  /// the unanalyzed newer release.
  final Map<ReleasePlatform, LatestRelease>? latestReleases;

  /// The newest unanalyzed release per platform, whenever one
  /// exists. A platform is omitted when its most recent release
  /// has already been analyzed. Independent of `latest_releases`:
  /// both can be present (a newer release than the analyzed one
  /// is being processed) or only `pending_releases` can be
  /// present (no release on the platform has been analyzed yet).
  final Map<ReleasePlatform, PendingRelease>? pendingReleases;

  /// Server-emitted URL for the app's launcher icon, sourced from
  /// the most recent analyzed iOS release (or Android, when iOS
  /// has no analyzed release with an icon). Requires the same
  /// auth as the rest of the apps API. The URL embeds the picked
  /// release's id as a `v` query parameter so it can be cached
  /// indefinitely; when a different release becomes the icon
  /// source the URL changes and clients re-fetch. Omitted when
  /// no analyzed release has an icon.
  final String? iconUrl;

  /// Converts an [AppMetadata] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'app_id': appId,
      'display_name': displayName,
      'latest_release_version': latestReleaseVersion,
      'latest_patch_number': latestPatchNumber,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'platforms': platforms?.map((e) => e.toJson()).toList(),
      'latest_releases': latestReleases?.map(
        (key, value) => MapEntry(key.toJson(), value.toJson()),
      ),
      'pending_releases': pendingReleases?.map(
        (key, value) => MapEntry(key.toJson(), value.toJson()),
      ),
      'icon_url': iconUrl,
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
    listHash(platforms),
    mapHash(latestReleases),
    mapHash(pendingReleases),
    iconUrl,
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
        updatedAt == other.updatedAt &&
        listsEqual(platforms, other.platforms) &&
        mapsEqual(latestReleases, other.latestReleases) &&
        mapsEqual(pendingReleases, other.pendingReleases) &&
        iconUrl == other.iconUrl;
  }
}
