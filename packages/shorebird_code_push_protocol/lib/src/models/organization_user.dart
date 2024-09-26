import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

part 'organization_user.g.dart';

/// {@template organization_user}
/// A member of an organization and their role in that organization.
/// {@endtemplate}
@JsonSerializable()
class OrganizationUser {
  /// {@macro organization_user}
  OrganizationUser({
    required this.user,
    required this.role,
  });

  /// Converts this [OrganizationUser] to a JSON map.
  factory OrganizationUser.fromJson(Map<String, dynamic> json) =>
      _$OrganizationUserFromJson(json);

  /// Converts a JSON map to an [OrganizationUser].
  Map<String, dynamic> toJson() => _$OrganizationUserToJson(this);

  /// The user that is a member of the organization.
  final User user;

  /// The role [user] has in the organization.
  final OrganizationRole role;
}
