import 'package:json_annotation/json_annotation.dart';

part 'app_metadata.g.dart';

/// {@template app_metadata}
/// A single app which contains zero or more releases.
/// {@endtemplate}
@JsonSerializable()
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

  /// Converts a Map<String, dynamic> to an [AppMetadata]
  factory AppMetadata.fromJson(Map<String, dynamic> json) =>
      _$AppMetadataFromJson(json);

  /// Converts a [AppMetadata] to a Map<String, dynamic>
  Map<String, dynamic> toJson() => _$AppMetadataToJson(this);

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
}
