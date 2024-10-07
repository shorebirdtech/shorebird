import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

extension OrganizationDisplay on Organization {
  String get displayName => switch (organizationType) {
        OrganizationType.team => name,
        OrganizationType.personal => 'Personal',
      };
}
