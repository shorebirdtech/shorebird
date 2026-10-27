import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/orgs/organization_scoped_command.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template members_list_command}
/// `shorebird members list`
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
      'Example output (space-separated: user id  email  role  status):\n'
      '  12  alice@acme.com  owner  member\n'
      '  -  bob@acme.com  developer  invited (expires 2026-11-10)\n\n'
      'Invite someone with `shorebird members add <email>`.\n\n'
      '${ShorebirdCommand.jsonHint(
        'shorebird members list --org-id 42 --json',
      )}';

  @override
  Future<int> run() async {
    final (:membership, :errorCode) = await resolveOrganization();
    if (errorCode != null) return errorCode;
    final organization = membership!.organization;

    late final List<OrganizationUser> members;
    late final List<InvitationSummary> invitations;
    final fetchError = await guardApiCall(
      () async {
        members = await codePushClientWrapper.getOrganizationUsers(
          organizationId: organization.id,
        );
        invitations = await codePushClientWrapper.getOrganizationInvitations(
          organizationId: organization.id,
        );
      },
      code: JsonErrorCode.fetchFailed,
      message:
          'Failed to fetch the members of organization ${organization.id}.',
    );
    if (fetchError != null) return fetchError;

    if (isJsonMode) {
      emitJsonSuccess({
        'organization_id': organization.id,
        'members': [
          for (final member in members)
            {
              'status': 'member',
              'user_id': member.user.id,
              'email': member.user.email,
              'name': member.user.displayName,
              'role': member.role.value,
            },
          for (final invite in invitations)
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
    for (final invite in invitations) {
      logger.info(
        '-  ${lightCyan.wrap(invite.email)}  ${invite.role.value}  '
        'invited (expires ${_date(invite.expiresAt)})',
      );
    }
    return ExitCode.success.code;
  }
}

/// [time]'s UTC calendar date, as YYYY-MM-DD.
String _date(DateTime time) => time.toUtc().toIso8601String().substring(0, 10);
