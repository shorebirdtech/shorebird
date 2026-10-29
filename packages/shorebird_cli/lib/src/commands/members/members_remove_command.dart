import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/confirm_delete.dart';
import 'package:shorebird_cli/src/commands/enterprises/enterprise_scoped_command.dart';
import 'package:shorebird_cli/src/commands/finish_in_console.dart';
import 'package:shorebird_cli/src/commands/members/member_target.dart';
import 'package:shorebird_cli/src/commands/orgs/organization_scoped_command.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_web_console.dart';
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
        FinishInConsole,
        MemberLookup,
        EnterpriseMemberLookup {
  /// {@macro members_remove_command}
  ///
  /// With [enterpriseRoute], it is `shorebird enterprise members remove`,
  /// which confirms in the console, so it takes no --yes.
  MembersRemoveCommand({bool enterpriseRoute = false}) {
    if (!enterpriseRoute) {
      addConfirmDeleteOptions();
      addOrganizationScopeOption();
    }
    addEnterpriseScope(route: enterpriseRoute);
  }

  @override
  String get name => 'remove';

  @override
  List<String> get aliases => const ['delete'];

  @override
  String get invocation => isEnterpriseRoute
      ? 'shorebird enterprise members remove <email or user id>'
      : 'shorebird members remove <email, user id or invitation id>';

  @override
  String get description =>
      isEnterpriseRoute ? _enterpriseDescription : _organizationDescription;

  String get _enterpriseDescription =>
      'Opens the console to remove someone from your enterprise and every '
      'organization in it. That is permanent and signs them out '
      'everywhere, so it is confirmed there; nothing changes until you '
      'confirm. Needs an owner or admin of the enterprise.\n\n'
      'Example output:\n'
      '  Opening the Shorebird console to remove bob@acme.com from '
      '"Acme":\n'
      '  https://console.shorebird.dev/enterprise/people\n\n'
      'Under --json, or without a terminal, it opens nothing and fails '
      'with console_required, naming the URL.';

  String get _organizationDescription =>
      'Removes a member from an organization, or cancels a pending '
      'invitation (named by email or invitation id).\n\n'
      'In a terminal, asks for confirmation. Pass --$yesArgName to skip the '
      'prompt; it is required when not running interactively (no terminal, '
      'CI, or --json).\n\n'
      'Example output:\n'
      '  Removed bob@acme.com from "Acme Corp".\n\n'
      'To remove someone from an enterprise, run '
      '`shorebird enterprise members remove`.\n\n'
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
            '$commandLine bob@acme.com.',
      );
    }
    final user = rest.single.trim();
    final scopeError = rejectConflictingScope(takesUserArgument: true);
    if (scopeError != null) return scopeError;
    if (enterpriseScope) return _removeFromEnterprise(user);

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

  /// Removing someone from an enterprise is permanent and revokes every
  /// session and API key on their account, so it finishes in the console
  /// (ADR-0026).
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
    return finishInConsole(
      action: 'remove $label from "${enterprise.name}"',
      url: ShorebirdWebConsole.uri('enterprise/people'),
    );
  }
}
