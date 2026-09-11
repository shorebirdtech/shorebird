import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template patch}
/// An over-the-air update which is applied to a specific release.
/// All patches have a patch number (auto-incrementing integer) and
/// multiple patches can be published for a given release.
/// {@endtemplate}
@immutable
class Patch {
  /// {@macro patch}
  const Patch({
    required this.id,
    required this.number,
    this.notes,
  });

  /// Converts a `Map<String, dynamic>` to a [Patch].
  factory Patch.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'Patch',
      json,
      () => Patch(
        id: json['id'] as int,
        number: json['number'] as int,
        notes: json['notes'] as String?,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static Patch? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return Patch.fromJson(json);
  }

  /// The unique patch identifier.
  final int id;

  /// The patch number. A larger number equates to a newer patch.
  final int number;

  /// Freeform notes associated with the patch, if any.
  final String? notes;

  /// Converts a [Patch] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'number': number,
      'notes': notes,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    number,
    notes,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Patch &&
        id == other.id &&
        number == other.number &&
        notes == other.notes;
  }
}
