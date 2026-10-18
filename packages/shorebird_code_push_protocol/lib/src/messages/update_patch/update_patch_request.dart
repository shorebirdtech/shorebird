import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template update_patch_request}
/// The request body for PATCH
/// /apps/{appId}/releases/{releaseId}/patches/{patchId}.
/// {@endtemplate}
@immutable
class UpdatePatchRequest {
  /// {@macro update_patch_request}
  const UpdatePatchRequest({
    this.notes,
    this.hidden,
  });

  /// Converts a `Map<String, dynamic>` to a [UpdatePatchRequest].
  factory UpdatePatchRequest.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'UpdatePatchRequest',
      json,
      () => UpdatePatchRequest(
        notes: json['notes'] as String?,
        hidden: json['hidden'] as bool?,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static UpdatePatchRequest? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return UpdatePatchRequest.fromJson(json);
  }

  /// Freeform notes about the patch. If null, notes are unchanged.
  final String? notes;

  /// Whether to hide the patch from the console's patch list (true) or
  /// show it again (false). Display only: a hidden patch stays live on
  /// its track. If null, it is unchanged.
  final bool? hidden;

  /// Converts a [UpdatePatchRequest] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'notes': ?notes,
      'hidden': ?hidden,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    notes,
    hidden,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UpdatePatchRequest &&
        notes == other.notes &&
        hidden == other.hidden;
  }
}
