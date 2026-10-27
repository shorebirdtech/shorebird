import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/confirm_delete.dart';
import 'package:shorebird_cli/src/commands/members/member_target.dart';
import 'package:shorebird_cli/src/commands/orgs/organization_scoped_command.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template members_remove_command}
/// `shorebird members remove <user>`
/// Remove a member from an organization, or cancel a pending invitation.
/// {@endtemplate}
class MembersRemoveCommand extends ShorebirdCommand
    with OrganizationScopedCommand, ConfirmDelete {
  /// {@macro members_remove_command}
  MembersRemoveCommand() {
    addConfirmDeleteOptions();
    addOrganizationScopeOption();
  }

  @override
  String get name => 'remove';

  @override
  List<String> get aliases => const ['delete'];

  @override
  String get invocation => 'shorebird members remove <email or user id>';

  @override
  String get description =>
      'Removes a member from an organization, or cancels the pending '
      'invitation sent to an email.\n\n'
      'In a terminal, asks for confirmation. Pass --$yesArgName to skip the '
      'prompt; it is required when not running interactively (no terminal, '
      'CI, or --json).\n\n'
      'Example output:\n'
      '  Removed bob@acme.com from "Acme Corp".\n\n'
      '${ShorebirdCommand.jsonHint(
        'shorebird members remove bob@acme.com --org-id 42 --yes --json',
      )}';

  @override
  Future<int> run() async {
    final rest = results.rest;
    if (rest.length != 1) {
      return reportError(
        message:
            'Name one member by email or user id: '
            'shorebird members remove bob@acme.com.',
      );
    }
    final user = rest.single;

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

    final (:member, :invite) = findMemberTarget(
      user,
      members: members,
      invitations: invitations,
    );

    if (member != null) {
      final email = member.user.email;
      final confirmError = confirmDelete(
        name: email,
        description: '$email from "${organization.name}"',
        consequence:
            '$email will lose access to "${organization.name}" and its '
            'apps.',
      );
      if (confirmError != null) return confirmError;

      final removeError = await guardApiCall(
        () => codePushClientWrapper.removeOrganizationUser(
          organizationId: organization.id,
          userId: member.user.id,
        ),
        code: JsonErrorCode.softwareError,
        message:
            'Failed to remove $email from organization ${organization.id}.',
      );
      if (removeError != null) return removeError;
      return _report(
        organization: organization,
        email: email,
        status: 'member',
        text: 'Removed $email from "${organization.name}".',
      );
    }

    if (invite != null) {
      final email = invite.email;
      final confirmError = confirmDelete(
        name: email,
        description: 'the invitation for $email',
        consequence:
            'The invitation $email was sent to join "${organization.name}" '
            'will stop working.',
      );
      if (confirmError != null) return confirmError;

      final revokeError = await guardApiCall(
        () => codePushClientWrapper.revokeOrganizationInvitation(
          organizationId: organization.id,
          invitationId: invite.id,
        ),
        code: JsonErrorCode.softwareError,
        message: 'Failed to cancel the invitation for $email.',
      );
      if (revokeError != null) return revokeError;
      return _report(
        organization: organization,
        email: email,
        status: 'invited',
        text: 'Cancelled the invitation for $email to "${organization.name}".',
      );
    }

    return reportError(
      message:
          '"$user" is not a member of "${organization.name}" and has no '
          'pending invitation.',
      hint:
          'Run `shorebird members list --org-id ${organization.id}` to see '
          'its members.',
    );
  }

  int _report({
    required Organization organization,
    required String email,
    required String status,
    required String text,
  }) {
    if (isJsonMode) {
      emitJsonSuccess({
        'organization_id': organization.id,
        'email': email,
        'removed': status,
      });
    } else {
      logger.success(text);
    }
    return ExitCode.success.code;
  }
}
