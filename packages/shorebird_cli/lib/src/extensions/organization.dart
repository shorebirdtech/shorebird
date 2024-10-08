import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template organization_display}
/// Returns the user-facing display name of an [Organization].
/// {@endtemplate}
extension OrganizationDisplay on Organization {
  /// {@macro organization_display}
  String displayName({required PrivateUser user}) => switch (organizationType) {
        OrganizationType.team => name,
        OrganizationType.personal => user.displayName ?? user.email,
      };
}
