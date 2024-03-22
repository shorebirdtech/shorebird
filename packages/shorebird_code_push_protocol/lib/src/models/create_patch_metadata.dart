import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/src/models/models.dart';

part 'create_patch_metadata.g.dart';

/// {@template create_patch_metadata}
/// Information about a patch, used for debugging purposes.
/// {@endtemplate}
@JsonSerializable()
class CreatePatchMetadata {
  /// {@macro create_patch_metadata}
  const CreatePatchMetadata({
    required this.usedIgnoreAssetChangesFlag,
    required this.hasAssetChanges,
    required this.usedIgnoreNativeChangesFlag,
    required this.hasNativeChanges,
    required this.environment,
  });

  /// Converts a Map<String, dynamic> to a [CreatePatchMetadata]
  factory CreatePatchMetadata.fromJson(Map<String, dynamic> json) =>
      _$CreatePatchMetadataFromJson(json);

  /// Converts a [CreatePatchMetadata] to a Map<String, dynamic>
  Map<String, dynamic> toJson() => _$CreatePatchMetadataToJson(this);

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
}
