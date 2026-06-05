import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template patch_adoption_range}
/// The effective (post-clamp) window the response covers.
/// {@endtemplate}
@immutable
class PatchAdoptionRange {
  /// {@macro patch_adoption_range}
  const PatchAdoptionRange({
    required this.start,
    required this.end,
  });

  /// Converts a `Map<String, dynamic>` to a [PatchAdoptionRange].
  factory PatchAdoptionRange.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'PatchAdoptionRange',
      json,
      () => PatchAdoptionRange(
        start: DateTime.parse(json['start'] as String),
        end: DateTime.parse(json['end'] as String),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static PatchAdoptionRange? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return PatchAdoptionRange.fromJson(json);
  }

  /// Window start (UTC, inclusive).
  final DateTime start;

  /// Window end (UTC, exclusive).
  final DateTime end;

  /// Converts a [PatchAdoptionRange] to a `Map<String, dynamic>`.
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
    return other is PatchAdoptionRange &&
        start == other.start &&
        end == other.end;
  }
}
