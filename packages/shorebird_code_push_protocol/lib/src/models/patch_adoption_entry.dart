import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/patch_adoption_point.dart';
import 'package:shorebird_code_push_protocol/src/models/release_platform.dart';

/// {@template patch_adoption_entry}
/// Cumulative adoption for one patch number of the release, across
/// every platform with a patch under that number. Values are
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
    this.rolledBackPlatforms,
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
        rolledBackPlatforms: (json['rolled_back_platforms'] as List?)
            ?.map<ReleasePlatform>((e) => ReleasePlatform.fromJson(e as String))
            .toList(),
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

  /// The platforms with a patch under this number. The denominator
  /// counts only devices on these platforms.
  final List<ReleasePlatform> targetPlatforms;

  /// Whether the patch has been rolled back. When several platforms
  /// share the number, true only when every one of them is.
  final bool isRolledBack;

  /// The platforms whose patch under this number is rolled back.
  /// Unstable: this may change shape until patch linking ships.
  final List<ReleasePlatform>? rolledBackPlatforms;

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
      'rolled_back_platforms': ?rolledBackPlatforms
          ?.map((e) => e.toJson())
          .toList(),
      'series': series.map((e) => e.toJson()).toList(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    patchNumber,
    listHash(targetPlatforms),
    isRolledBack,
    listHash(rolledBackPlatforms),
    listHash(series),
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PatchAdoptionEntry &&
        patchNumber == other.patchNumber &&
        listsEqual(targetPlatforms, other.targetPlatforms) &&
        isRolledBack == other.isRolledBack &&
        listsEqual(rolledBackPlatforms, other.rolledBackPlatforms) &&
        listsEqual(series, other.series);
  }
}
