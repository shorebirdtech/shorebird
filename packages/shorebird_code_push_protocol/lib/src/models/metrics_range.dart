import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template metrics_range}
/// The effective (post-default, post-clamp) window a metrics response —
/// or one window of a metrics envelope — covers. Always echoed by the
/// server; clients must treat it as authoritative rather than reusing
/// the requested range.
/// {@endtemplate}
@immutable
class MetricsRange {
  /// {@macro metrics_range}
  const MetricsRange({
    required this.start,
    required this.end,
  });

  /// Converts a `Map<String, dynamic>` to a [MetricsRange].
  factory MetricsRange.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'MetricsRange',
      json,
      () => MetricsRange(
        start: DateTime.parse(json['start'] as String),
        end: DateTime.parse(json['end'] as String),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static MetricsRange? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return MetricsRange.fromJson(json);
  }

  /// Window start (UTC, inclusive).
  final DateTime start;

  /// Window end (UTC, exclusive).
  final DateTime end;

  /// Converts a [MetricsRange] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'start': start.toIso8601String(),
      'end': end.toIso8601String(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    start,
    end,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MetricsRange && start == other.start && end == other.end;
  }
}
