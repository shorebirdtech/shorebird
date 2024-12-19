import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

part 'release_patch.g.dart';

/// {@template release_patch}
/// A patch for a given release.
/// {@endtemplate}
// TODO(bryanoltman): consolidate this with [Patch]
@JsonSerializable()
class ReleasePatch extends Equatable {
  /// {@macro release_patch}
  const ReleasePatch({
    required this.id,
    required this.number,
    required this.channel,
    required this.artifacts,
    required this.isRolledBack,
  });

  /// Converts a `Map<String, dynamic>` to a [ReleasePatch]
  factory ReleasePatch.fromJson(Map<String, dynamic> json) =>
      _$ReleasePatchFromJson(json);

  /// Converts a [ReleasePatch] to a `Map<String, dynamic>`
  Json toJson() => _$ReleasePatchToJson(this);

  /// The patch id.
  final int id;

  /// The patch number.
  final int number;

  /// The channel associated with the patch.
  final String? channel;

  /// The associated patch artifacts.
  final List<PatchArtifact> artifacts;

  /// Whether the patch has been rolled back.
  final bool isRolledBack;

  @override
  List<Object?> get props => [id, number, channel, artifacts, isRolledBack];
}
