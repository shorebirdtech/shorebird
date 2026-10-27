import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/role.dart';

/// {@template get_invitation_response}
/// The response body for GET /invitations/{invitationId}. Exactly one
/// of `organization_id` and `app_id` is non-null.
/// {@endtemplate}
@immutable
class GetInvitationResponse {
  /// {@macro get_invitation_response}
  const GetInvitationResponse({
    required this.id,
    required this.organizationId,
    required this.appId,
    required this.targetName,
    required this.inviterEmail,
    required this.email,
    required this.role,
    required this.expiresAt,
  });

  /// Converts a `Map<String, dynamic>` to a [GetInvitationResponse].
  factory GetInvitationResponse.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'GetInvitationResponse',
      json,
      () => GetInvitationResponse(
        id: json['id'] as String,
        organizationId: checkedKey(json, 'organization_id') as int?,
        appId: checkedKey(json, 'app_id') as String?,
        targetName: json['target_name'] as String,
        inviterEmail: json['inviter_email'] as String,
        email: json['email'] as String,
        role: Role.fromJson(json['role'] as String),
        expiresAt: DateTime.parse(json['expires_at'] as String),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static GetInvitationResponse? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return GetInvitationResponse.fromJson(json);
  }

  /// The ID of the invitation.
  final String id;

  /// The organization the invitation is to, or null for an app invitation.
  final int? organizationId;

  /// The app the invitation is to, or null for an organization invitation.
  final String? appId;

  /// The organization's name or the app's display name.
  final String targetName;

  /// The email of the user who sent the invitation.
  final String inviterEmail;

  /// The email address the invitation was sent to.
  final String email;

  /// A role that a user can have relative to an Organization or App.
  final Role role;

  /// When the invitation stops being valid.
  final DateTime expiresAt;

  /// Converts a [GetInvitationResponse] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'organization_id': organizationId,
      'app_id': appId,
      'target_name': targetName,
      'inviter_email': inviterEmail,
      'email': email,
      'role': role.toJson(),
      'expires_at': expiresAt.toUtc().toIso8601String(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    organizationId,
    appId,
    targetName,
    inviterEmail,
    email,
    role,
    expiresAt,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GetInvitationResponse &&
        id == other.id &&
        organizationId == other.organizationId &&
        appId == other.appId &&
        targetName == other.targetName &&
        inviterEmail == other.inviterEmail &&
        email == other.email &&
        role == other.role &&
        expiresAt == other.expiresAt;
  }
}
