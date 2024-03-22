import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/src/models/models.dart';

part 'update_release_metadata.g.dart';

/// {@template release_metadata}
/// Information about the creation of patch, used for debugging purposes.
/// {@endtemplate}
@JsonSerializable()
class UpdateReleaseMetadata {
  /// {@macro release_metadata}
  const UpdateReleaseMetadata({
    required this.generatedApks,
    required this.environment,
  });

  /// Converts a Map<String, dynamic> to a [UpdateReleaseMetadata].
  factory UpdateReleaseMetadata.fromJson(Map<String, dynamic> json) =>
      _$UpdateReleaseMetadataFromJson(json);

  /// Converts a [UpdateReleaseMetadata] to a Map<String, dynamic>.
  Map<String, dynamic> toJson() => _$UpdateReleaseMetadataToJson(this);

  /// Whether the user opted to generate an APK for the release (android-only).
  final bool? generatedApks;

  /// Properties about the environment in which the update to the release was
  /// performed.
  final BuildEnvironmentMetadata environment;
}
