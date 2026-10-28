import 'package:collection/collection.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_web_console.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// The roles `shorebird members add` and `set-role` can grant, in the
/// order help text lists them: the roles some plan offers members. `owner`
/// is left out: ownership moves in the console (ADR-0026), and invitations
/// can't grant it. `appManager` needs the enterprise plan; the server says
/// so.
const grantableRoles = [
  Role.admin,
  Role.appManager,
  Role.developer,
  Role.viewer,
];

/// Help text for `--role` on member commands.
final memberRoleHelp =
    'The role: ${grantableRoles.map((r) => r.value).join(', ')}.';

/// Why the CLI won't move or take away ownership, with where to do it.
String get ownershipInConsoleMessage =>
    'Ownership is transferred in the console, not the CLI: '
    '${ShorebirdWebConsole.baseUri}';

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
  if (role == Role.owner) return (role: null, error: ownershipInConsoleMessage);
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
/// invitation, or neither. `invitationsHidden` is true when the user's role
/// can't see invitations, so one wasn't looked for.
typedef MemberTarget = ({
  OrganizationUser? member,
  InvitationSummary? invite,
  bool invitationsHidden,
});

/// Finds the member or pending invitation a `USER` argument names.
mixin MemberLookup on ShorebirdCommand {
  /// Finds what [user] names in [organization]: a member by user id or
  /// email, else a pending invitation by email or invitation id. Emails
  /// match ignoring case. Invitations are fetched only when no member
  /// matches.
  ///
  /// Returns the target, or an exit code once a failed fetch is reported.
  Future<({MemberTarget? target, int? errorCode})> findMemberTarget(
    String user, {
    required Organization organization,
  }) async {
    final id = int.tryParse(user);
    final email = user.toLowerCase();
    final failure =
        'Failed to fetch the members of organization ${organization.id}.';

    late final List<OrganizationUser> members;
    final membersError = await guardApiCall(
      () async => members = await codePushClientWrapper.getOrganizationUsers(
        organizationId: organization.id,
      ),
      code: JsonErrorCode.fetchFailed,
      message: failure,
    );
    if (membersError != null) return (target: null, errorCode: membersError);
    final member = members.firstWhereOrNull(
      (m) => m.user.id == id || m.user.email.toLowerCase() == email,
    );
    if (member != null) {
      return (
        target: (member: member, invite: null, invitationsHidden: false),
        errorCode: null,
      );
    }

    late final List<InvitationSummary>? invitations;
    final invitationsError = await guardApiCall(
      () async => invitations = await codePushClientWrapper
          .maybeGetOrganizationInvitations(organizationId: organization.id),
      code: JsonErrorCode.fetchFailed,
      message: failure,
    );
    if (invitationsError != null) {
      return (target: null, errorCode: invitationsError);
    }
    final invite = invitations?.firstWhereOrNull(
      (i) => i.id == user || i.email.toLowerCase() == email,
    );
    return (
      target: (
        member: null,
        invite: invite,
        invitationsHidden: invitations == null,
      ),
      errorCode: null,
    );
  }
}

/// Help text for `--role` with `--enterprise-id`.
final enterpriseRoleHelp =
    'With --enterprise-id, the enterprise role: '
    '${EnterpriseRole.values.map((r) => r.value).join(', ')}.';

/// Parses a `--role` value given with `--enterprise-id`, returning the
/// enterprise role or why it isn't one. Matching ignores case, dashes and
/// underscores, so `billing-manager` names [EnterpriseRole.billingManager].
({EnterpriseRole? role, String? error}) parseEnterpriseRole(String arg) {
  String normalize(String s) =>
      s.toLowerCase().replaceAll('-', '').replaceAll('_', '');
  final role = EnterpriseRole.values.firstWhereOrNull(
    (r) => normalize(r.value) == normalize(arg),
  );
  if (role != null) return (role: role, error: null);
  return (
    role: null,
    error:
        '"$arg" is not an enterprise role. Choose one of: '
        '${EnterpriseRole.values.map((r) => r.value).join(', ')}.',
  );
}

/// Finds the member of an enterprise's directory a `USER` argument names.
mixin EnterpriseMemberLookup on ShorebirdCommand {
  /// Finds the member [user] names in [enterprise]'s directory, by user id
  /// or email (ignoring case).
  ///
  /// Returns the member, or an exit code once a failed fetch or no match is
  /// reported.
  Future<({EnterpriseMember? member, int? errorCode})> findEnterpriseMember(
    String user, {
    required EnterpriseMembership enterprise,
  }) async {
    late final List<EnterpriseMember> members;
    final fetchError = await guardApiCall(
      () async => members = await codePushClientWrapper.getEnterpriseMembers(
        enterpriseId: enterprise.id,
      ),
      code: JsonErrorCode.fetchFailed,
      message: 'Failed to fetch the members of enterprise ${enterprise.id}.',
    );
    if (fetchError != null) return (member: null, errorCode: fetchError);

    final id = int.tryParse(user);
    final email = user.toLowerCase();
    final member = members.firstWhereOrNull(
      (m) => m.userId == id || m.email?.toLowerCase() == email,
    );
    if (member != null) return (member: member, errorCode: null);
    return (
      member: null,
      errorCode: reportError(
        message: '"$user" is not a member of "${enterprise.name}".',
        hint:
            'Run `shorebird members list --enterprise-id ${enterprise.id}` '
            'to see its members.',
      ),
    );
  }
}

/// How a user an enterprise lists is named in output: their email, else
/// their display name, else their user id.
String enterpriseUserLabel({
  required int userId,
  String? email,
  String? displayName,
}) => email ?? displayName ?? 'user $userId';
