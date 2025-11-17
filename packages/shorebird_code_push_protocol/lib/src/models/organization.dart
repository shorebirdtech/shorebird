import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:meta/meta.dart';

part 'organization.g.dart';

/// {@template organization_type}
/// Distinguishes between automatically created organizations that are limited
/// to a single user and organizations that support multiple users.
/// {@endtemplate}
enum OrganizationType {
  /// A personal organization is created for every user for their own apps.
  personal,

  /// A team organization is created for multiple users to collaborate on apps.
  team,
}

/// {@template organization}
/// An Organization groups users and apps together. Organizations can be
/// personal (single-user) or team (multi-user). Organizations have exactly one
/// owner, but can have multiple admins and members.
/// {@endtemplate}
@JsonSerializable()
class Organization extends Equatable {
  /// {@macro organization}
  const Organization({
    required this.id,
    required this.name,
    required this.organizationType,
    required this.createdAt,
    required this.updatedAt,
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
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Organization(
    id: id,
    name: name,
    organizationType: organizationType,
    createdAt: createdAt ?? DateTime.now(),
    updatedAt: updatedAt ?? DateTime.now(),
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

  /// When this organization was created.
  final DateTime createdAt;

  /// When this organization was last updated.
  final DateTime updatedAt;

  @override
  List<Object?> get props => [id, name, organizationType, createdAt, updatedAt];
}
