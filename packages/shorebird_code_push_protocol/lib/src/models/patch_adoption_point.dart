import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template patch_adoption_point}
/// One point in a patch's adoption series: the cumulative distinct
/// devices on `patch >= patch_number` (`devices`) over the patch's target
/// (`target`), and their ratio (`adoption_pct`), for one bucket.
/// {@endtemplate}
@immutable
class PatchAdoptionPoint {
  /// {@macro patch_adoption_point}
  const PatchAdoptionPoint({
    required this.period,
    required this.devices,
    required this.target,
    required this.adoptionPct,
  });

  /// Converts a `Map<String, dynamic>` to a [PatchAdoptionPoint].
  factory PatchAdoptionPoint.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'PatchAdoptionPoint',
      json,
      () => PatchAdoptionPoint(
        period: maybeParseDateTime(checkedKey(json, 'period') as String?),
        devices: json['devices'] as int,
        target: json['target'] as int,
        adoptionPct: (json['adoption_pct'] as num).toDouble(),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static PatchAdoptionPoint? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return PatchAdoptionPoint.fromJson(json);
  }

  /// The bucket start (UTC), or null when the response is a single
  /// full-window value (no granularity requested).
  final DateTime? period;

  /// Distinct devices running patch `>= patch_number` on the patch's
  /// target platform(s) within this bucket (an HLL count).
  final int devices;

  /// Distinct devices on the release whose platform the patch targets —
  /// the patch's reachable denominator — within this bucket.
  final int target;

  /// `devices / target`, in [0.0, 1.0] (0 when `target` is 0). Server
  /// is the source of truth; clients should render this value rather
  /// than recomputing it.
  final double adoptionPct;

  /// Converts a [PatchAdoptionPoint] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'period': period?.toIso8601String(),
      'devices': devices,
      'target': target,
      'adoption_pct': adoptionPct,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    period,
    devices,
    target,
    adoptionPct,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PatchAdoptionPoint &&
        period == other.period &&
        devices == other.devices &&
        target == other.target &&
        adoptionPct == other.adoptionPct;
  }
}
