import 'package:json_annotation/json_annotation.dart';

part 'artifact.g.dart';

/// {@template artifact}
/// An artifact represents the contents of an update (patch) for a specific
/// platform and architecture.
/// {@endtemplate}
@JsonSerializable()
class Artifact {
  /// {@macro artifact}
  const Artifact({
    required this.arch,
    required this.platform,
    required this.url,
    required this.hash,
  });

  /// Converts a Map<String, dynamic> to an [Artifact]
  factory Artifact.fromJson(Map<String, dynamic> json) =>
      _$ArtifactFromJson(json);

  /// Converts an [Artifact] to a Map<String, dynamic>
  Map<String, dynamic> toJson() => _$ArtifactToJson(this);

  /// The architecture of the artifact.
  /// e.g. arm64, x86_64
  final String arch;

  /// The platform of the artifact.
  /// e.g. android, ios
  final String platform;

  /// The URL of the artifact.
  final String url;

  /// The hash of the artifact.
  final String hash;
}
