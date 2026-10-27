// Some OpenAPI specs flatten inline schemas into class names long
// enough that `dart format` can't keep imports and call sites under
// 80 cols as bare identifiers.
// ignore_for_file: lines_longer_than_80_chars
import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/role.dart';

sealed class CreateOrganizationInvitation201Response {
  const CreateOrganizationInvitation201Response();

  factory CreateOrganizationInvitation201Response.fromJson(
    Map<String, dynamic> json,
  ) {
    final discriminator = json['type'];
    return switch (discriminator) {
      'invitation' => CreateInvitationResponse.fromJson(json),
      'member' => AddedMemberResponse.fromJson(json),
      _ => throw FormatException(
        "Unknown type '$discriminator' for CreateOrganizationInvitation201Response",
      ),
    };
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static CreateOrganizationInvitation201Response? maybeFromJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return null;
    }
    return CreateOrganizationInvitation201Response.fromJson(json);
  }

  /// Require all subclasses to implement toJson.
  Map<String, dynamic> toJson();
}

/// {@template create_invitation_response}
/// The response body for creating an invitation to an organization or
/// an app.
/// {@endtemplate}
@immutable
final class CreateInvitationResponse
    extends CreateOrganizationInvitation201Response {
  /// {@macro create_invitation_response}
  const CreateInvitationResponse({
    required this.email,
  });

  /// Converts a `Map<String, dynamic>` to a [CreateInvitationResponse].
  factory CreateInvitationResponse.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'CreateInvitationResponse',
      json,
      () => CreateInvitationResponse(
        email: json['email'] as String,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static CreateInvitationResponse? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return CreateInvitationResponse.fromJson(json);
  }

  /// Always `invitation`: what was created is a pending invitation,
  /// not a membership.
  String get type => 'invitation';

  /// The email the invitation was sent to.
  final String email;

  /// Converts a [CreateInvitationResponse] to a `Map<String, dynamic>`.
  @override
  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'email': email,
    };
  }

  @override
  int get hashCode => email.hashCode;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CreateInvitationResponse && email == other.email;
  }
}

/// {@template added_member_response}
/// The response body for inviting an account that is already in the
/// directory of the organization's enterprise: it was added as a member
/// at once, and no invitation was sent.
/// {@endtemplate}
@immutable
final class AddedMemberResponse
    extends CreateOrganizationInvitation201Response {
  /// {@macro added_member_response}
  const AddedMemberResponse({
    required this.email,
    required this.role,
  });

  /// Converts a `Map<String, dynamic>` to an [AddedMemberResponse].
  factory AddedMemberResponse.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'AddedMemberResponse',
      json,
      () => AddedMemberResponse(
        email: json['email'] as String,
        role: Role.fromJson(json['role'] as String),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static AddedMemberResponse? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return AddedMemberResponse.fromJson(json);
  }

  /// Always `member`: what was created is a membership, not a pending
  /// invitation.
  String get type => 'member';

  /// The email the request named.
  final String email;

  /// A role that a user can have relative to an Organization or App.
  final Role role;

  /// Converts an [AddedMemberResponse] to a `Map<String, dynamic>`.
  @override
  Map<String, dynamic> toJson() {
    return {
      'type': type,
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
    return other is AddedMemberResponse &&
        email == other.email &&
        role == other.role;
  }
}
