import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

part 'release.g.dart';

/// {@template release}
/// A release build of an application that is distributed to devices.
/// A release can have zero or more patches applied to it.
/// {@endtemplate}
@JsonSerializable()
class Release {
  /// {@macro release}
  const Release({
    required this.id,
    required this.appId,
    required this.version,
    required this.flutterRevision,
    required this.displayName,
    required this.platformStatuses,
  });

  /// Converts a Map<String, dynamic> to a [Release]
  factory Release.fromJson(Map<String, dynamic> json) =>
      _$ReleaseFromJson(json);

  /// Converts a [Release] to a Map<String, dynamic>
  Map<String, dynamic> toJson() => _$ReleaseToJson(this);

  /// The ID of the release;
  final int id;

  /// The ID of the app.
  final String appId;

  /// The version of the release.
  final String version;

  /// The Flutter revision used to create the release.
  final String flutterRevision;

  /// The display name for the release
  final String? displayName;

  /// The status of the release for each platform.
  final Map<ReleasePlatform, ReleaseStatus> platformStatuses;
}
