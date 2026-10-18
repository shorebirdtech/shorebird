import 'package:shorebird_code_push_protocol/src/models/patch_artifact.dart';
import 'package:shorebird_code_push_protocol/src/models/release_patch.dart';

/// Application-level behavior on [ReleasePatch] that does not fit in the
/// OpenAPI schema.
extension ReleasePatchExtensions on ReleasePatch {
  /// Returns a copy of this [ReleasePatch] with the given fields replaced by
  /// the new values.
  ReleasePatch copyWith({
    int? id,
    int? number,
    String? channel,
    List<PatchArtifact>? artifacts,
    bool? isRolledBack,
    String? notes,
    DateTime? hiddenAt,
  }) => ReleasePatch(
    id: id ?? this.id,
    number: number ?? this.number,
    channel: channel ?? this.channel,
    artifacts: artifacts ?? this.artifacts,
    isRolledBack: isRolledBack ?? this.isRolledBack,
    notes: notes ?? this.notes,
    hiddenAt: hiddenAt ?? this.hiddenAt,
  );
}
