import 'package:json_annotation/json_annotation.dart';

part 'artifact.g.dart';

/// {@template artifact}
/// A single patch which contains zero or more artifacts.
/// {@endtemplate}
@JsonSerializable()
class Artifact {
  /// {@macro artifact}
  const Artifact({
    required this.id,
    required this.patchId,
    required this.arch,
    required this.platform,
    required this.hash,
    required this.url,
  });

  /// Converts a Map<String, dynamic> to a [Artifact]
  factory Artifact.fromJson(Map<String, dynamic> json) =>
      _$ArtifactFromJson(json);

  /// Converts a [Artifact] to a Map<String, dynamic>
  Map<String, dynamic> toJson() => _$ArtifactToJson(this);

  /// The ID of the artifact;
  final int id;

  /// The ID of the patch.
  final int patchId;

  /// The arch of the artifact.
  final String arch;

  /// The platform of the artifact.
  final String platform;

  /// The hash of the artifact.
  final String hash;

  /// The url of the artifact.
  final String url;
}
