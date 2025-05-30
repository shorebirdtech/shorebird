import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

part 'release.g.dart';

/// {@template release}
/// A release build of an application that is distributed to devices.
/// A release can have zero or more patches applied to it.
/// {@endtemplate}
@JsonSerializable()
@immutable
class Release extends Equatable {
  /// {@macro release}
  const Release({
    required this.id,
    required this.appId,
    required this.version,
    required this.flutterRevision,
    required this.flutterVersion,
    required this.displayName,
    required this.platformStatuses,
    required this.createdAt,
    required this.updatedAt,
    this.notes,
  });

  /// Converts a `Map<String, dynamic>` to a [Release]
  factory Release.fromJson(Map<String, dynamic> json) =>
      _$ReleaseFromJson(json);

  /// Converts a [Release] to a `Map<String, dynamic>`
  Map<String, dynamic> toJson() => _$ReleaseToJson(this);

  /// The ID of the release;
  final int id;

  /// The ID of the app.
  final String appId;

  /// The version of the release.
  final String version;

  /// The Flutter revision used to create the release.
  final String flutterRevision;

  /// The Flutter version used to create the release.
  ///
  /// This field is optional because it was newly added and
  /// older releases do not have this information.
  final String? flutterVersion;

  /// The display name for the release
  final String? displayName;

  /// The status of the release for each platform.
  final Map<ReleasePlatform, ReleaseStatus> platformStatuses;

  /// The date and time the release was created.
  final DateTime createdAt;

  /// The date and time the release was last updated.
  final DateTime updatedAt;

  /// The notes associated with the release, if any.
  ///
  /// This value is freeform text with no assumptions about content or format.
  final String? notes;

  @override
  List<Object?> get props => [
    id,
    appId,
    version,
    flutterRevision,
    flutterVersion,
    displayName,
    platformStatuses,
    createdAt,
    updatedAt,
    notes,
  ];
}
