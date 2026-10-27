import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/invitation_target_type.dart';

/// {@template get_invitation_preview_response}
/// The response body for GET /invitations/{invitationId}/preview: only
/// what a sign-in screen needs, and no personal information.
/// {@endtemplate}
@immutable
class GetInvitationPreviewResponse {
  /// {@macro get_invitation_preview_response}
  const GetInvitationPreviewResponse({
    required this.targetName,
    required this.type,
  });

  /// Converts a `Map<String, dynamic>` to a [GetInvitationPreviewResponse].
  factory GetInvitationPreviewResponse.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'GetInvitationPreviewResponse',
      json,
      () => GetInvitationPreviewResponse(
        targetName: json['target_name'] as String,
        type: InvitationTargetType.fromJson(json['type'] as String),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static GetInvitationPreviewResponse? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return GetInvitationPreviewResponse.fromJson(json);
  }

  /// The organization's name or the app's display name.
  final String targetName;

  /// Whether the invitation is to an organization or an app.
  final InvitationTargetType type;

  /// Converts a [GetInvitationPreviewResponse] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'target_name': targetName,
      'type': type.toJson(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    targetName,
    type,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GetInvitationPreviewResponse &&
        targetName == other.targetName &&
        type == other.type;
  }
}
