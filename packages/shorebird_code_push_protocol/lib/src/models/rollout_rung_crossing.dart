import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template rollout_rung_crossing}
/// The first time a sample's adoption share reached one rung. Only rungs
/// that have been crossed appear in `rung_crossings`; rungs not (yet)
/// crossed are absent, not null-filled.
/// {@endtemplate}
@immutable
class RolloutRungCrossing {
  /// {@macro rollout_rung_crossing}
  const RolloutRungCrossing({
    required this.rung,
    required this.crossedAt,
  });

  /// Converts a `Map<String, dynamic>` to a [RolloutRungCrossing].
  factory RolloutRungCrossing.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'RolloutRungCrossing',
      json,
      () => RolloutRungCrossing(
        rung: (json['rung'] as num).toDouble(),
        crossedAt: DateTime.parse(json['crossed_at'] as String),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static RolloutRungCrossing? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return RolloutRungCrossing.fromJson(json);
  }

  /// The rung that was crossed, as a share (e.g. 0.25).
  final double rung;

  /// The first hour (UTC) whose adoption share reached the rung.
  /// Hour-bucketed while `created_at` is exact, so it can precede
  /// `created_at` by up to an hour; consumers clamp the transit
  /// at zero.
  final DateTime crossedAt;

  /// Converts a [RolloutRungCrossing] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'rung': rung,
      'crossed_at': crossedAt.toIso8601String(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    rung,
    crossedAt,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RolloutRungCrossing &&
        rung == other.rung &&
        crossedAt == other.crossedAt;
  }
}
