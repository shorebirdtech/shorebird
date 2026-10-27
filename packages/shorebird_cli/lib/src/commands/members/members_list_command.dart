import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/orgs/organization_scoped_command.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template members_list_command}
/// `shorebird orgs members list`
/// List an organization's members and pending invitations.
/// {@endtemplate}
class MembersListCommand extends ShorebirdCommand
    with OrganizationScopedCommand {
  /// {@macro members_list_command}
  MembersListCommand() {
    addOrganizationScopeOption();
  }

  @override
  String get name => 'list';

  @override
  String get description =>
      "Lists an organization's members and pending invitations.\n\n"
      'Example output (space-separated: id  email  role  status):\n'
      '  12  alice@acme.com  owner  member\n'
      '  0b6c...  bob@acme.com  developer  invited (expires 2026-11-10)\n\n'
      'The id is the user id of a member and the invitation id of a pending '
      'invitation; `members set-role` and `members remove` take either, or '
      'the email.\n\n'
      'Invite someone with `shorebird orgs members add <email>`.\n\n'
      '${ShorebirdCommand.jsonHint(
        'shorebird orgs members list --org-id 42 --json',
      )}';

  @override
  Future<int> run() async {
    final (:membership, :errorCode) = await resolveOrganization();
    if (errorCode != null) return errorCode;
    final organization = membership!.organization;

    late final List<OrganizationUser> members;
    late final List<InvitationSummary>? invitations;
    final fetchError = await guardApiCall(
      () async {
        members = await codePushClientWrapper.getOrganizationUsers(
          organizationId: organization.id,
        );
        invitations = await codePushClientWrapper
            .maybeGetOrganizationInvitations(organizationId: organization.id);
      },
      code: JsonErrorCode.fetchFailed,
      message:
          'Failed to fetch the members of organization ${organization.id}.',
    );
    if (fetchError != null) return fetchError;

    // The auditor role can't see invitations; list the members anyway.
    const invitationsHiddenMessage =
        'Pending invitations are not shown: your role in this organization '
        "can't see them.";

    if (isJsonMode) {
      emitJsonSuccess({
        'organization_id': organization.id,
        'invitations_shown': invitations != null,
        'members': [
          for (final member in members)
            {
              'status': 'member',
              'user_id': member.user.id,
              'email': member.user.email,
              'name': member.user.displayName,
              'role': member.role.value,
            },
          for (final invite in invitations ?? <InvitationSummary>[])
            {
              'status': 'invited',
              'invitation_id': invite.id,
              'email': invite.email,
              'role': invite.role.value,
              'invited_at': invite.createdAt.toUtc().toIso8601String(),
              'expires_at': invite.expiresAt.toUtc().toIso8601String(),
            },
        ],
      });
      return ExitCode.success.code;
    }

    for (final member in members) {
      logger.info(
        '${member.user.id}  ${lightCyan.wrap(member.user.email)}  '
        '${member.role.value}  member',
      );
    }
    final shownInvitations = invitations;
    if (shownInvitations == null) {
      logger.warn(invitationsHiddenMessage);
      return ExitCode.success.code;
    }
    for (final invite in shownInvitations) {
      logger.info(
        '${invite.id}  ${lightCyan.wrap(invite.email)}  ${invite.role.value}  '
        'invited (expires ${_date(invite.expiresAt)})',
      );
    }
    return ExitCode.success.code;
  }
}

/// [time]'s UTC calendar date, as YYYY-MM-DD.
String _date(DateTime time) => time.toUtc().toIso8601String().substring(0, 10);
