import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/src/models/models.dart';

part 'create_patch_metadata.g.dart';

/// {@template create_patch_metadata}
/// Information about a patch, used for debugging purposes.
///
/// Collection of this information is done to help Shorebird users debug any
/// later failures in their builds.
///
/// We do not collect Personally Identifying Information (e.g. no paths,
/// argument lists, etc.) in accordance with our privacy policy:
/// https://shorebird.dev/privacy/
/// {@endtemplate}
@JsonSerializable()
class CreatePatchMetadata extends Equatable {
  /// {@macro create_patch_metadata}
  const CreatePatchMetadata({
    required this.releasePlatform,
    required this.usedIgnoreAssetChangesFlag,
    required this.hasAssetChanges,
    required this.usedIgnoreNativeChangesFlag,
    required this.hasNativeChanges,
    required this.environment,
  });

  // coverage:ignore-start
  /// Creates a [CreatePatchMetadata] with overridable default values for
  /// testing purposes.
  factory CreatePatchMetadata.forTest({
    ReleasePlatform releasePlatform = ReleasePlatform.android,
    bool usedIgnoreAssetChangesFlag = false,
    bool hasAssetChanges = false,
    bool usedIgnoreNativeChangesFlag = false,
    bool hasNativeChanges = false,
    BuildEnvironmentMetadata? environment,
  }) =>
      CreatePatchMetadata(
        releasePlatform: releasePlatform,
        usedIgnoreAssetChangesFlag: usedIgnoreAssetChangesFlag,
        hasAssetChanges: hasAssetChanges,
        usedIgnoreNativeChangesFlag: usedIgnoreNativeChangesFlag,
        hasNativeChanges: hasNativeChanges,
        environment: environment ?? BuildEnvironmentMetadata.forTest(),
      );
  // coverage:ignore-end

  /// Converts a Map<String, dynamic> to a [CreatePatchMetadata]
  factory CreatePatchMetadata.fromJson(Map<String, dynamic> json) =>
      _$CreatePatchMetadataFromJson(json);

  /// Converts a [CreatePatchMetadata] to a Map<String, dynamic>
  Map<String, dynamic> toJson() => _$CreatePatchMetadataToJson(this);

  /// The platform for which the patch was created.
  final ReleasePlatform releasePlatform;

  /// Whether the `--allow-asset-diffs` flag was used.
  final bool usedIgnoreAssetChangesFlag;

  /// Whether asset changes were detected in the patch.
  final bool hasAssetChanges;

  /// Whether the `--allow-native-diffs` flag was used.
  final bool usedIgnoreNativeChangesFlag;

  /// Whether native code changes were detected in the patch.
  final bool hasNativeChanges;

  /// Properties about the environment in which the patch was created.
  final BuildEnvironmentMetadata environment;

  @override
  List<Object?> get props => [
        releasePlatform,
        usedIgnoreAssetChangesFlag,
        hasAssetChanges,
        usedIgnoreNativeChangesFlag,
        hasNativeChanges,
        environment,
      ];
}
