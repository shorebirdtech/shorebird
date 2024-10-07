import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template organization_display}
/// Returns the user-facing display name of an [Organization].
/// {@endtemplate}
extension OrganizationDisplay on Organization {
  /// {@macro organization_display}
  String get displayName => switch (organizationType) {
        OrganizationType.team => name,
        OrganizationType.personal => 'Personal',
      };
}
