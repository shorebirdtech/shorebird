import 'package:collection/collection.dart';
import 'package:shorebird_cli/src/shorebird_web_console.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// The roles `shorebird members add` and `set-role` can grant, in the order
/// help text lists them. `owner` is left out: ownership moves in the console
/// (ADR-0026), and invitations can't grant it.
const grantableRoles = [
  Role.admin,
  Role.appManager,
  Role.developer,
  Role.viewer,
  Role.auditor,
];

/// Help text for `--role` on member commands.
final memberRoleHelp =
    'The role: ${grantableRoles.map((r) => r.value).join(', ')}.';

/// Parses a `--role` value, returning the role or why it can't be granted.
///
/// Matching ignores case, dashes and underscores, so `app-manager` and
/// `app_manager` both name [Role.appManager].
({Role? role, String? error}) parseMemberRole(String arg) {
  String normalize(String s) =>
      s.toLowerCase().replaceAll('-', '').replaceAll('_', '');
  final role = Role.values.firstWhereOrNull(
    (r) => normalize(r.value) == normalize(arg),
  );
  if (role == Role.owner) {
    return (
      role: null,
      error:
          'Ownership is transferred in the console, not the CLI: '
          '${ShorebirdWebConsole.baseUri}',
    );
  }
  if (role == null || !grantableRoles.contains(role)) {
    return (
      role: null,
      error:
          '"$arg" is not a role you can grant. Choose one of: '
          '${grantableRoles.map((r) => r.value).join(', ')}.',
    );
  }
  return (role: role, error: null);
}

/// Who a `USER` argument names in an organization: a member, a pending
/// invitation, or neither.
typedef MemberTarget = ({OrganizationUser? member, InvitationSummary? invite});

/// Finds the member or pending invitation that [arg] names: a member by user
/// id or email, or an invitation by email. Emails match ignoring case.
MemberTarget findMemberTarget(
  String arg, {
  required List<OrganizationUser> members,
  required List<InvitationSummary> invitations,
}) {
  final id = int.tryParse(arg);
  final email = arg.toLowerCase();
  final member = members.firstWhereOrNull(
    (m) => m.user.id == id || m.user.email.toLowerCase() == email,
  );
  if (member != null) return (member: member, invite: null);
  final invite = invitations.firstWhereOrNull(
    (i) => i.email.toLowerCase() == email,
  );
  return (member: null, invite: invite);
}
