import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template role}
/// A role that a user can have relative to an [Organization] or [App].
/// {@endtemplate}
enum Role {
  /// User that created the organization.
  owner,

  /// Users who have permissions to manage the organization.
  admin,

  /// Users who are part of the organization but have limited permissions.
  developer,

  /// Users who are not part of the organization but have visibility into it via
  /// app collaborator permissions.
  none,
}
