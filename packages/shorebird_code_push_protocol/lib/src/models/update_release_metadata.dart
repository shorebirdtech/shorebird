import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/src/models/models.dart';

part 'update_release_metadata.g.dart';

/// {@template release_metadata}
/// Information about the creation of patch, used for debugging purposes.
///
/// Collection of this information is done to help Shorebird users debug any
/// later failures in their builds.
///
/// We do not collect Personally Identifying Information (e.g. no paths,
/// argument lists, etc.) in accordance with our privacy policy:
/// https://shorebird.dev/privacy/
/// {@endtemplate}
@JsonSerializable()
class UpdateReleaseMetadata extends Equatable {
  /// {@macro release_metadata}
  const UpdateReleaseMetadata({
    required this.releasePlatform,
    required this.flutterVersionOverride,
    required this.generatedApks,
    required this.environment,
  });

  // coverage:ignore-start
  /// Creates a [UpdateReleaseMetadata] with overridable default values for
  /// testing purposes.
  factory UpdateReleaseMetadata.forTest({
    ReleasePlatform releasePlatform = ReleasePlatform.android,
    String? flutterVersionOverride = '1.2.3',
    bool? generatedApks = false,
    BuildEnvironmentMetadata? environment,
  }) =>
      UpdateReleaseMetadata(
        releasePlatform: releasePlatform,
        flutterVersionOverride: flutterVersionOverride,
        generatedApks: generatedApks,
        environment: environment ?? BuildEnvironmentMetadata.forTest(),
      );
  // coverage:ignore-end

  /// Converts a Map<String, dynamic> to a [UpdateReleaseMetadata].
  factory UpdateReleaseMetadata.fromJson(Map<String, dynamic> json) =>
      _$UpdateReleaseMetadataFromJson(json);

  /// Converts a [UpdateReleaseMetadata] to a Map<String, dynamic>.
  Map<String, dynamic> toJson() => _$UpdateReleaseMetadataToJson(this);

  /// The platform for which the patch was created.
  final ReleasePlatform releasePlatform;

  /// The Flutter version specified by the user, if any.
  ///
  /// Reason: different Flutter versions have different performance
  /// characteristics and features. Additionally, this helps us understand which
  /// versions of Flutter are most commonly used.
  final String? flutterVersionOverride;

  /// Whether the user opted to generate an APK for the release (android-only).
  ///
  /// Reason: if this flag is present, it produces different build artifacts,
  /// which may affect the build process.
  final bool? generatedApks;

  /// Properties about the environment in which the update to the release was
  /// performed.
  ///
  /// Reason: see [BuildEnvironmentMetadata].
  final BuildEnvironmentMetadata environment;

  @override
  List<Object?> get props => [
        releasePlatform,
        flutterVersionOverride,
        generatedApks,
        environment,
      ];
}
