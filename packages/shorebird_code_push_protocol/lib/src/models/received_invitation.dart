import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/role.dart';

/// {@template received_invitation}
/// A pending invitation sent to the signed-in user. Exactly one of
/// `organization_id` and `app_id` is set.
/// {@endtemplate}
@immutable
class ReceivedInvitation {
  /// {@macro received_invitation}
  const ReceivedInvitation({
    required this.id,
    required this.targetName,
    required this.inviterEmail,
    required this.role,
    required this.createdAt,
    required this.expiresAt,
    this.organizationId,
    this.appId,
  });

  /// Converts a `Map<String, dynamic>` to a [ReceivedInvitation].
  factory ReceivedInvitation.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'ReceivedInvitation',
      json,
      () => ReceivedInvitation(
        id: json['id'] as String,
        organizationId: json['organization_id'] as int?,
        appId: json['app_id'] as String?,
        targetName: json['target_name'] as String,
        inviterEmail: json['inviter_email'] as String,
        role: Role.fromJson(json['role'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
        expiresAt: DateTime.parse(json['expires_at'] as String),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static ReceivedInvitation? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return ReceivedInvitation.fromJson(json);
  }

  /// The ID of the invitation, which accepting or declining it takes.
  final String id;

  /// The organization the invitation is to, for an organization invitation.
  final int? organizationId;

  /// The app the invitation is to, for an app invitation.
  final String? appId;

  /// The organization's name or the app's display name.
  final String targetName;

  /// The email of the user who sent the invitation.
  final String inviterEmail;

  /// A role that a user can have relative to an Organization or App.
  final Role role;

  /// When the invitation was sent.
  final DateTime createdAt;

  /// When the invitation stops being valid.
  final DateTime expiresAt;

  /// Converts a [ReceivedInvitation] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'organization_id': ?organizationId,
      'app_id': ?appId,
      'target_name': targetName,
      'inviter_email': inviterEmail,
      'role': role.toJson(),
      'created_at': createdAt.toUtc().toIso8601String(),
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
    role,
    createdAt,
    expiresAt,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ReceivedInvitation &&
        id == other.id &&
        organizationId == other.organizationId &&
        appId == other.appId &&
        targetName == other.targetName &&
        inviterEmail == other.inviterEmail &&
        role == other.role &&
        createdAt == other.createdAt &&
        expiresAt == other.expiresAt;
  }
}
