import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/role.dart';

/// {@template create_organization_invitation_request}
/// The request body for POST /organizations/{organizationId}/invitations.
/// {@endtemplate}
@immutable
class CreateOrganizationInvitationRequest {
  /// {@macro create_organization_invitation_request}
  const CreateOrganizationInvitationRequest({
    required this.email,
    required this.role,
  });

  /// Converts a `Map<String, dynamic>` to a
  /// [CreateOrganizationInvitationRequest].
  factory CreateOrganizationInvitationRequest.fromJson(
    Map<String, dynamic> json,
  ) {
    return parseFromJson(
      'CreateOrganizationInvitationRequest',
      json,
      () => CreateOrganizationInvitationRequest(
        email: json['email'] as String,
        role: Role.fromJson(json['role'] as String),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static CreateOrganizationInvitationRequest? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return CreateOrganizationInvitationRequest.fromJson(json);
  }

  /// The email address to send the invitation to.
  final String email;

  /// A role that a user can have relative to an Organization or App.
  final Role role;

  /// Converts a [CreateOrganizationInvitationRequest]
  /// to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'email': email,
      'role': role.toJson(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    email,
    role,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CreateOrganizationInvitationRequest &&
        email == other.email &&
        role == other.role;
  }
}
