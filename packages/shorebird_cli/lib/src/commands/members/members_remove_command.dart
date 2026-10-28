import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/confirm_delete.dart';
import 'package:shorebird_cli/src/commands/enterprises/enterprise_scoped_command.dart';
import 'package:shorebird_cli/src/commands/members/member_target.dart';
import 'package:shorebird_cli/src/commands/orgs/organization_scoped_command.dart';
import 'package:shorebird_cli/src/formatters/formatters.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template members_remove_command}
/// `shorebird members remove <user>`
/// Remove a member from an organization, or cancel a pending invitation.
/// {@endtemplate}
class MembersRemoveCommand extends ShorebirdCommand
    with
        OrganizationScopedCommand,
        EnterpriseScopedCommand,
        ConfirmDelete,
        MemberLookup,
        EnterpriseMemberLookup {
  /// {@macro members_remove_command}
  MembersRemoveCommand() {
    addConfirmDeleteOptions();
    addOrganizationScopeOption();
    addEnterpriseScopeOption(
      help:
          'Remove them from this enterprise (e.g. "7") and every '
          'organization in it instead. Needs an owner or admin of the '
          'enterprise.',
    );
  }

  @override
  String get name => 'remove';

  @override
  List<String> get aliases => const ['delete'];

  @override
  String get invocation =>
      'shorebird members remove <email, user id or invitation id>';

  @override
  String get description =>
      'Removes a member from an organization, or cancels a pending '
      'invitation (named by email or invitation id).\n\n'
      'In a terminal, asks for confirmation. Pass --$yesArgName to skip the '
      'prompt; it is required when not running interactively (no terminal, '
      'CI, or --json).\n\n'
      'Example output:\n'
      '  Removed bob@acme.com from "Acme Corp".\n\n'
      'With --enterprise-id, removes them from the enterprise and every '
      'organization in it, revokes their sessions and API keys, and prints '
      'the access removed.\n\n'
      '${ShorebirdCommand.jsonHint(
        'shorebird members remove bob@acme.com --org-id 42 --yes --json',
      )}';

  @override
  Future<int> run() async {
    final rest = results.rest;
    if (rest.length != 1 || rest.single.trim().isEmpty) {
      return reportError(
        message:
            'Name one member by email or user id: '
            'shorebird members remove bob@acme.com.',
      );
    }
    final user = rest.single.trim();
    final scopeError = rejectOrganizationAndEnterprise();
    if (scopeError != null) return scopeError;
    if (enterpriseIdOption != null) return _removeFromEnterprise(user);

    final (:membership, :errorCode) = await resolveOrganization();
    if (errorCode != null) return errorCode;
    final organization = membership!.organization;

    final (:target, errorCode: lookupError) = await findMemberTarget(
      user,
      organization: organization,
    );
    if (lookupError != null) return lookupError;
    final (:member, :invite, :invitationsHidden) = target!;

    if (member != null) {
      final email = member.user.email;
      if (member.role == Role.owner) {
        return reportError(
          message: '$email owns "${organization.name}" and cannot be removed.',
          hint: ownershipInConsoleMessage,
        );
      }
      final confirmError = confirmDelete(
        name: email,
        verb: 'Remove',
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
        verb: 'Cancel',
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
      message: invitationsHidden
          ? '"$user" is not a member of "${organization.name}".'
          : '"$user" is not a member of "${organization.name}" and has no '
                'pending invitation.',
      hint: invitationsHidden
          ? "Your role can't see pending invitations, so none was looked for."
          : 'Run `shorebird members list --org-id ${organization.id}` '
                'to see '
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
        'status': status,
      });
    } else {
      logger.success(text);
    }
    return ExitCode.success.code;
  }

  Future<int> _removeFromEnterprise(String user) async {
    final (:membership, :errorCode) = await resolveEnterprise();
    if (errorCode != null) return errorCode;
    final enterprise = membership!;

    final (:member, errorCode: lookupError) = await findEnterpriseMember(
      user,
      enterprise: enterprise,
    );
    if (lookupError != null) return lookupError;
    final label = enterpriseUserLabel(
      userId: member!.userId,
      email: member.email,
      displayName: member.displayName,
    );

    final confirmError = confirmDelete(
      name: label,
      verb: 'Remove',
      description: '$label from "${enterprise.name}" and all its organizations',
      consequence:
          '$label will lose access to every organization and app in '
          '"${enterprise.name}", and their sessions and API keys will be '
          'revoked.',
    );
    if (confirmError != null) return confirmError;

    late final RemoveEnterpriseMember200Response removed;
    final removeError = await guardApiCall(
      () async => removed = await codePushClientWrapper.removeEnterpriseMember(
        enterpriseId: enterprise.id,
        userId: member.userId,
      ),
      code: JsonErrorCode.softwareError,
      message: 'Failed to remove $label from enterprise ${enterprise.id}.',
    );
    if (removeError != null) return removeError;

    if (isJsonMode) {
      emitJsonSuccess({
        'enterprise_id': enterprise.id,
        'user_id': member.userId,
        'email': member.email,
        'removed': removed.toJson(),
      });
      return ExitCode.success.code;
    }
    final organizations = removed.organizations
        .map((o) => '"${o.organizationName}" (${o.role.value})')
        .join(', ');
    logger
      ..success('Removed $label from "${enterprise.name}".')
      ..info(
        'Organizations left: '
        '${organizations.isEmpty ? 'none' : organizations}.',
      )
      ..info(
        'Also removed ${formatCount(removed.appGrants.length, 'app grant')}, '
        'and revoked ${formatCount(removed.sessionsRevoked, 'session')}, '
        "${formatCount(removed.apiKeysRevoked, 'API key')} and "
        "${formatCount(removed.invitationsRevoked, 'invitation')}.",
      );
    return ExitCode.success.code;
  }
}
