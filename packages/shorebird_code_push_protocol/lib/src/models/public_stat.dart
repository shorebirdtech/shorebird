import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template public_stat}
/// The latest value of one public stat.
/// {@endtemplate}
@immutable
class PublicStat {
  /// {@macro public_stat}
  const PublicStat({
    required this.value,
    required this.perSecond,
    required this.asOf,
  });

  /// Converts a `Map<String, dynamic>` to a [PublicStat].
  factory PublicStat.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'PublicStat',
      json,
      () => PublicStat(
        value: json['value'] as int,
        perSecond: (checkedKey(json, 'per_second') as num?)?.toDouble(),
        asOf: DateTime.parse(json['as_of'] as String),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static PublicStat? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return PublicStat.fromJson(json);
  }

  /// The stat's value as of `as_of`.
  final int value;

  /// How fast the value was rising over the last three hours, per second.
  /// Null for a stat that does not tick.
  final double? perSecond;

  /// When `value` is current to.
  final DateTime asOf;

  /// Converts a [PublicStat] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'value': value,
      'per_second': perSecond,
      'as_of': asOf.toUtc().toIso8601String(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    value,
    perSecond,
    asOf,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PublicStat &&
        value == other.value &&
        perSecond == other.perSecond &&
        asOf == other.asOf;
  }
}
