// Some OpenAPI specs flatten inline schemas into class names long
// enough that `dart format` can't keep imports and call sites under
// 80 cols as bare identifiers.
import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/patch_artifact.dart';

/// {@template release_patch}
/// A patch for a given release.
/// {@endtemplate}
@immutable
class ReleasePatch {
  /// {@macro release_patch}
  const ReleasePatch({
    required this.id,
    required this.number,
    required this.artifacts,
    required this.isRolledBack,
    this.channel,
    this.notes,
  });

  /// Converts a `Map<String, dynamic>` to a [ReleasePatch].
  factory ReleasePatch.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'ReleasePatch',
      json,
      () => ReleasePatch(
        id: json['id'] as int,
        number: json['number'] as int,
        channel: json['channel'] as String?,
        artifacts: (json['artifacts'] as List)
            .map<PatchArtifact>(
              (e) => PatchArtifact.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
        isRolledBack: json['is_rolled_back'] as bool,
        notes: json['notes'] as String?,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static ReleasePatch? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return ReleasePatch.fromJson(json);
  }

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

  /// Freeform notes associated with the patch, if any.
  final String? notes;

  /// Converts a [ReleasePatch] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'number': number,
      'channel': channel,
      'artifacts': artifacts.map((e) => e.toJson()).toList(),
      'is_rolled_back': isRolledBack,
      'notes': notes,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    number,
    channel,
    listHash(artifacts),
    isRolledBack,
    notes,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ReleasePatch &&
        id == other.id &&
        number == other.number &&
        channel == other.channel &&
        listsEqual(artifacts, other.artifacts) &&
        isRolledBack == other.isRolledBack &&
        notes == other.notes;
  }
}
