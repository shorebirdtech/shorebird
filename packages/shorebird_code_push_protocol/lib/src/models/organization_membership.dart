import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

part 'organization_membership.g.dart';

/// {@template organization_membership}
/// An organization and the current user's role in that organization.
/// {@endtemplate}
@JsonSerializable()
class OrganizationMembership extends Equatable {
  /// {@macro organization_membership}
  const OrganizationMembership({
    required this.organization,
    required this.role,
  });

  /// Deserializes the [OrganizationMembership] from aJSON map.
  factory OrganizationMembership.fromJson(Map<String, dynamic> json) =>
      _$OrganizationMembershipFromJson(json);

  /// Serializes the [OrganizationMembership] to a JSON map.
  Map<String, dynamic> toJson() => _$OrganizationMembershipToJson(this);

  /// The organization.
  final Organization organization;

  /// The user's role in the organization.
  final Role role;

  @override
  List<Object?> get props => [organization, role];
}
