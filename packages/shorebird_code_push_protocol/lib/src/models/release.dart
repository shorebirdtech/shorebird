import 'package:json_annotation/json_annotation.dart';

part 'release.g.dart';

/// {@template release}
/// An app release.
/// {@endtemplate}
@JsonSerializable()
class Release {
  /// {@macro release}
  const Release({
    required this.id,
    required this.appId,
    required this.version,
    required this.displayName,
  });

  /// Converts a Map<String, dynamic> to a [Release]
  factory Release.fromJson(Map<String, dynamic> json) =>
      _$ReleaseFromJson(json);

  /// Converts a [Release] to a Map<String, dynamic>
  Map<String, dynamic> toJson() => _$ReleaseToJson(this);

  /// The ID of the artifact;
  final int id;

  /// The ID of the app.
  final String appId;

  /// The version of the release.
  final String version;

  /// The display name for the release
  final String? displayName;
}
