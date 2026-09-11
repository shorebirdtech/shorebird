import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/patch_adoption_point.dart';
import 'package:shorebird_code_push_protocol/src/models/release_platform.dart';

/// {@template patch_adoption_entry}
/// Cumulative adoption for one patch of the release. Values are
/// cumulative — "patch `>= patch_number`" — so they are monotonic
/// non-increasing in `patch_number`.
/// {@endtemplate}
@immutable
class PatchAdoptionEntry {
  /// {@macro patch_adoption_entry}
  const PatchAdoptionEntry({
    required this.patchNumber,
    required this.targetPlatforms,
    required this.isRolledBack,
    required this.series,
  });

  /// Converts a `Map<String, dynamic>` to a [PatchAdoptionEntry].
  factory PatchAdoptionEntry.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'PatchAdoptionEntry',
      json,
      () => PatchAdoptionEntry(
        patchNumber: json['patch_number'] as int,
        targetPlatforms: (json['target_platforms'] as List)
            .map<ReleasePlatform>((e) => ReleasePlatform.fromJson(e as String))
            .toList(),
        isRolledBack: json['is_rolled_back'] as bool,
        series: (json['series'] as List)
            .map<PatchAdoptionPoint>(
              (e) => PatchAdoptionPoint.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static PatchAdoptionEntry? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return PatchAdoptionEntry.fromJson(json);
  }

  /// The patch number these cumulative values are anchored at.
  final int patchNumber;

  /// The platform(s) the patch was built for (from its artifacts). The
  /// denominator counts only devices on these platforms.
  final List<ReleasePlatform> targetPlatforms;

  /// Whether the patch has been rolled back.
  final bool isRolledBack;

  /// The adoption series. Exactly one point (`period: null`) when no
  /// granularity was requested; otherwise one point per bucket, ordered
  /// by `period` ascending.
  final List<PatchAdoptionPoint> series;

  /// Converts a [PatchAdoptionEntry] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'patch_number': patchNumber,
      'target_platforms': targetPlatforms.map((e) => e.toJson()).toList(),
      'is_rolled_back': isRolledBack,
      'series': series.map((e) => e.toJson()).toList(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    patchNumber,
    listHash(targetPlatforms),
    isRolledBack,
    listHash(series),
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PatchAdoptionEntry &&
        patchNumber == other.patchNumber &&
        listsEqual(targetPlatforms, other.targetPlatforms) &&
        isRolledBack == other.isRolledBack &&
        listsEqual(series, other.series);
  }
}
