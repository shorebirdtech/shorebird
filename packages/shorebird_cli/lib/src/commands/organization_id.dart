import 'package:collection/collection.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// Why an `--org-id` value can't be used, worded the same by every command
/// that takes one.
typedef OrganizationIdError = ({String message, String hint});

/// Parses an `--org-id` value, returning the id or why it is invalid.
({int? id, OrganizationIdError? error}) parseOrganizationId(String arg) {
  final id = int.tryParse(arg);
  if (id != null) return (id: id, error: null);
  return (
    id: null,
    error: (
      message: '"$arg" is not a valid organization id.',
      hint:
          'Organization ids are integers, e.g. '
          '--${CommonArguments.orgIdArg.name} 42.',
    ),
  );
}

/// Finds the membership in organization [id] among [memberships], returning
/// it or why the caller can't use that organization.
({OrganizationMembership? membership, OrganizationIdError? error})
findOrganizationMembership({
  required int id,
  required List<OrganizationMembership> memberships,
}) {
  final membership = memberships.firstWhereOrNull(
    (m) => m.organization.id == id,
  );
  if (membership != null) return (membership: membership, error: null);
  return (
    membership: null,
    error: (
      message: 'You are not a member of organization $id.',
      hint: availableOrganizations(memberships),
    ),
  );
}

/// Lists [memberships]' organizations with their ids on one line, for a hint
/// that reads the same in human and JSON output.
String availableOrganizations(List<OrganizationMembership> memberships) {
  if (memberships.isEmpty) return 'You are not a member of any organization.';
  final organizations = memberships.map(
    (m) => '${m.organization.name} (${m.organization.id})',
  );
  return 'Your organizations: ${organizations.join(', ')}.';
}
