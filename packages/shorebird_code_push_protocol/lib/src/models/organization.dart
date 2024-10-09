import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:meta/meta.dart';

part 'organization.g.dart';

/// {@template organization_role}
/// A role that a user can have in an organization.
/// {@endtemplate}
enum OrganizationRole {
  /// User that created the organization.
  owner,

  /// Users who have permissions to manage the organization.
  admin,

  /// Users who are part of the organization but have limited permissions.
  member,

  /// Users who are not part of the organization but have visibility into it via
  /// app collaborator permissions.
  none;
}

/// {@template organization_type}
/// Distinguishes between automatically created organizations that are limited
/// to a single user and organizations that support multiple users.
/// {@endtemplate}
enum OrganizationType {
  /// A personal organization is created for every user for their own apps.
  personal,

  /// A team organization is created for multiple users to collaborate on apps.
  team;
}

/// {@template organization}
/// An Organization groups users and apps together. Organizations can be
/// personal (single-user) or team (multi-user). An Organization with a
/// [stripeCustomerId] may have a subscription.
/// {@endtemplate}
@JsonSerializable()
class Organization extends Equatable {
  /// {@macro organization}
  const Organization({
    required this.id,
    required this.name,
    required this.organizationType,
    required this.stripeCustomerId,
    required this.createdAt,
    required this.updatedAt,
    required this.patchOverageLimit,
  });

  /// Converts a [Map<String, dynamic>] to an [Organization].
  factory Organization.fromJson(Map<String, dynamic> json) =>
      _$OrganizationFromJson(json);

  // coverage:ignore-start
  /// Constructs an organization with arbitrary default values for testing.
  @visibleForTesting
  factory Organization.forTest({
    int id = 42,
    String name = 'Test Organization',
    OrganizationType organizationType = OrganizationType.personal,
    String? stripeCustomerId,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? patchOverageLimit,
  }) =>
      Organization(
        id: id,
        name: name,
        organizationType: organizationType,
        stripeCustomerId: stripeCustomerId,
        createdAt: createdAt ?? DateTime.now(),
        updatedAt: updatedAt ?? DateTime.now(),
        patchOverageLimit: patchOverageLimit ?? 0,
      );
  // coverage:ignore-end

  /// Converts this [Organization] to a JSON map
  Map<String, dynamic> toJson() => _$OrganizationToJson(this);

  /// The unique identifier for the organization.
  final int id;

  /// The name of the organization.
  final String name;

  /// The type of organization.
  final OrganizationType organizationType;

  /// The Stripe customer ID for the organization, if one exists.
  final String? stripeCustomerId;

  /// When this organization was created.
  final DateTime createdAt;

  /// When this organization was last updated.
  final DateTime updatedAt;

  /// The maximum number of patch installs that the user has agreed to pay for
  /// as part of a pay-as-you-go plan.
  final int? patchOverageLimit;

  @override
  List<Object?> get props => [
        id,
        name,
        organizationType,
        stripeCustomerId,
        createdAt,
        updatedAt,
        patchOverageLimit,
      ];
}
