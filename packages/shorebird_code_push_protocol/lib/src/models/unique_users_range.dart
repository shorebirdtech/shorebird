import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template unique_users_range}
/// The window the unique-users response covers.
/// {@endtemplate}
@immutable
class UniqueUsersRange {
  /// {@macro unique_users_range}
  const UniqueUsersRange({
    required this.start,
    required this.end,
  });

  /// Converts a `Map<String, dynamic>` to a [UniqueUsersRange].
  factory UniqueUsersRange.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'UniqueUsersRange',
      json,
      () => UniqueUsersRange(
        start: DateTime.parse(json['start'] as String),
        end: DateTime.parse(json['end'] as String),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static UniqueUsersRange? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return UniqueUsersRange.fromJson(json);
  }

  /// Window start (UTC, inclusive).
  final DateTime start;

  /// Window end (UTC, exclusive).
  final DateTime end;

  /// Converts a [UniqueUsersRange] to a `Map<String, dynamic>`.
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
    return other is UniqueUsersRange &&
        start == other.start &&
        end == other.end;
  }
}
