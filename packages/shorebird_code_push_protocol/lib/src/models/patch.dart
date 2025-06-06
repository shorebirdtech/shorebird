import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'patch.g.dart';

/// {@template patch}
/// An over the air update which is applied to a specific release.
/// All patches have a patch number (auto-incrementing integer) and
/// multiple patches can be published for a given app release version.
/// {@endtemplate}
@JsonSerializable()
class Patch extends Equatable {
  /// {@macro patch}
  const Patch({required this.id, required this.number, this.notes});

  /// Converts a `Map<String, dynamic>` to a [Patch]
  factory Patch.fromJson(Map<String, dynamic> json) => _$PatchFromJson(json);

  /// Converts a [Patch] to a `Map<String, dynamic>`
  Map<String, dynamic> toJson() => _$PatchToJson(this);

  /// The unique patch identifier.
  final int id;

  /// The patch number.
  /// A larger number equates to a newer patch.
  final int number;

  /// The notes associated with the patch, if any.
  ///
  /// This value is freeform text with no assumptions about content or format.
  final String? notes;

  @override
  List<Object?> get props => [id, number, notes];
}
