import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart'
    show Patch;
import 'package:shorebird_code_push_protocol/src/models/patch.dart' show Patch;

/// {@template create_patch_response}
/// The response body for POST /apps/{appId}/patches. Deliberately
/// narrower than [Patch]: a freshly-created patch has no `notes`
/// yet (those are set via PATCH /.../{patchId}), so this endpoint
/// exposes only the identifiers the client needs to upload
/// artifacts.
/// {@endtemplate}
@immutable
class CreatePatchResponse {
  /// {@macro create_patch_response}
  const CreatePatchResponse({
    required this.id,
    required this.number,
  });

  /// Converts a `Map<String, dynamic>` to a [CreatePatchResponse].
  factory CreatePatchResponse.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'CreatePatchResponse',
      json,
      () => CreatePatchResponse(
        id: json['id'] as int,
        number: json['number'] as int,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static CreatePatchResponse? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return CreatePatchResponse.fromJson(json);
  }

  /// The unique patch identifier.
  final int id;

  /// The patch number. A larger number equates to a newer patch.
  final int number;

  /// Converts a [CreatePatchResponse] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'number': number,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    number,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CreatePatchResponse &&
        id == other.id &&
        number == other.number;
  }
}
