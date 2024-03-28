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
    required this.linkPercentage,
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
    double? linkPercentage,
    BuildEnvironmentMetadata? environment,
  }) =>
      CreatePatchMetadata(
        releasePlatform: releasePlatform,
        usedIgnoreAssetChangesFlag: usedIgnoreAssetChangesFlag,
        hasAssetChanges: hasAssetChanges,
        usedIgnoreNativeChangesFlag: usedIgnoreNativeChangesFlag,
        hasNativeChanges: hasNativeChanges,
        linkPercentage: linkPercentage,
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
  ///
  /// Reason: this helps us understand how often prevalent the need to ignore
  /// asset changes is.
  final bool usedIgnoreAssetChangesFlag;

  /// Whether asset changes were detected in the patch.
  ///
  /// Reason: shorebird does not support asset changes in patches, and knowing
  /// that asset changes were detected can help explain unexpected behavior in
  /// a patch.
  final bool hasAssetChanges;

  /// Whether the `--allow-native-diffs` flag was used.
  ///
  /// Reason: this helps us understand how often prevalent the need to ignore
  /// native code changes is.
  final bool usedIgnoreNativeChangesFlag;

  /// Whether native code changes were detected in the patch.
  ///
  /// Reason: shorebird does not support native code changes in patches, and
  /// knowing that native code changes were detected can help explain unexpected
  /// behavior in a patch.
  final bool hasNativeChanges;

  /// The percentage of code that was linked in the patch.
  /// Generally, the higher the percentage, the better the patch performance
  /// since more code will be run on the CPU as opposed to the simulator.
  /// Note: link percentage is currently only available for iOS patches.
  final double? linkPercentage;

  /// Properties about the environment in which the patch was created.
  ///
  /// Reason: see [BuildEnvironmentMetadata].
  final BuildEnvironmentMetadata environment;

  @override
  List<Object?> get props => [
        releasePlatform,
        usedIgnoreAssetChangesFlag,
        hasAssetChanges,
        usedIgnoreNativeChangesFlag,
        hasNativeChanges,
        linkPercentage,
        environment,
      ];
}
