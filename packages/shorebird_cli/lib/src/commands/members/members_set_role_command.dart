import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/enterprises/enterprise_scoped_command.dart';
import 'package:shorebird_cli/src/commands/members/member_target.dart';
import 'package:shorebird_cli/src/commands/orgs/organization_scoped_command.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template members_set_role_command}
/// `shorebird members set-role <user> --role <role>`
/// Change a member's role in an organization.
/// {@endtemplate}
class MembersSetRoleCommand extends ShorebirdCommand
    with
        OrganizationScopedCommand,
        EnterpriseScopedCommand,
        MemberLookup,
        EnterpriseMemberLookup {
  /// {@macro members_set_role_command}
  ///
  /// With [enterpriseRoute], it is `shorebird enterprise members set-role`.
  MembersSetRoleCommand({bool enterpriseRoute = false}) {
    argParser.addOption(
      'role',
      help: enterpriseRoute ? enterpriseRoleHelp : memberRoleHelp,
      mandatory: true,
    );
    if (!enterpriseRoute) addOrganizationScopeOption();
    addEnterpriseScope(route: enterpriseRoute);
  }

  @override
  String get name => 'set-role';

  @override
  List<String> get aliases => const ['update'];

  @override
  String get invocation => isEnterpriseRoute
      ? 'shorebird enterprise members set-role <email or user id> '
            '--role <role>'
      : 'shorebird members set-role <email or user id> --role <role>';

  @override
  String get description =>
      isEnterpriseRoute ? _enterpriseDescription : _organizationDescription;

  String get _enterpriseDescription =>
      "Changes a member's enterprise role. Needs an owner of the "
      'enterprise.\n\n'
      'Example output:\n'
      '  Changed bob@acme.com from member to admin in "Acme".\n\n'
      '${ShorebirdCommand.jsonHint(
        'shorebird enterprise members set-role bob@acme.com --role '
        'admin --json',
      )}';

  String get _organizationDescription =>
      "Changes a member's role in an organization.\n\n"
      'Example output:\n'
      '  Changed bob@acme.com from developer to admin in "Acme Corp".\n\n'
      'For an enterprise role, run '
      '`shorebird enterprise members set-role`.\n\n'
      '${ShorebirdCommand.jsonHint(
        'shorebird members set-role bob@acme.com --role admin --org-id 42 '
        '--json',
      )}';

  @override
  Future<int> run() async {
    final rest = results.rest;
    if (rest.length != 1 || rest.single.trim().isEmpty) {
      return reportError(
        message:
            'Name one member by email or user id: '
            '$commandLine bob@acme.com --role admin.',
      );
    }
    final user = rest.single.trim();
    final scopeError = rejectConflictingScope(takesUserArgument: true);
    if (scopeError != null) return scopeError;
    if (enterpriseScope) return _setEnterpriseRole(user);

    final (:role, error: roleError) = parseMemberRole(
      results['role'] as String,
    );
    if (roleError != null) return reportError(message: roleError);

    final (:membership, :errorCode) = await resolveOrganization();
    if (errorCode != null) return errorCode;
    final organization = membership!.organization;

    final (:target, errorCode: lookupError) = await findMemberTarget(
      user,
      organization: organization,
    );
    if (lookupError != null) return lookupError;
    final (:member, :invite, :invitationsHidden) = target!;

    if (invite != null) {
      // The API can't change a pending invitation's role.
      return reportError(
        message:
            '${invite.email} has not accepted their invitation yet, so their '
            'role cannot be changed.',
        hint:
            'Cancel it and invite them again: shorebird members remove '
            '${invite.email} --org-id ${organization.id}, then shorebird '
            'members add ${invite.email} --role ${role!.value} --org-id '
            '${organization.id}.',
      );
    }
    if (member == null) {
      return reportError(
        message: '"$user" is not a member of "${organization.name}".',
        hint:
            'Run `shorebird members list --org-id ${organization.id}` '
            'to see '
            'its members.',
      );
    }
    if (member.role == Role.owner) {
      return reportError(
        message:
            '${member.user.email} owns "${organization.name}", so their role '
            'cannot be changed here.',
        hint: ownershipInConsoleMessage,
      );
    }

    final changed = member.role != role;
    if (changed) {
      final updateError = await guardApiCall(
        () => codePushClientWrapper.updateOrganizationUser(
          organizationId: organization.id,
          userId: member.user.id,
          role: role!,
        ),
        code: JsonErrorCode.softwareError,
        message: "Failed to change ${member.user.email}'s role.",
      );
      if (updateError != null) return updateError;
    }

    if (isJsonMode) {
      emitJsonSuccess({
        'organization_id': organization.id,
        'user_id': member.user.id,
        'email': member.user.email,
        'from_role': member.role.value,
        'to_role': role!.value,
        'changed': changed,
      });
      return ExitCode.success.code;
    }

    if (!changed) {
      logger.info(
        '${member.user.email} is already ${role!.value} in '
        '"${organization.name}"; nothing changed.',
      );
      return ExitCode.success.code;
    }
    logger.success(
      'Changed ${member.user.email} from ${member.role.value} to '
      '${role!.value} in "${organization.name}".',
    );
    return ExitCode.success.code;
  }

  Future<int> _setEnterpriseRole(String user) async {
    final (:role, error: roleError) = parseEnterpriseRole(
      results['role'] as String,
    );
    if (roleError != null) return reportError(message: roleError);

    final (:membership, :errorCode) = await resolveEnterprise();
    if (errorCode != null) return errorCode;
    final enterprise = membership!;
    if (enterprise.role != EnterpriseRole.owner) {
      return reportError(
        message:
            'Only owners of "${enterprise.name}" can change enterprise roles; '
            'you are ${enterprise.role.value}.',
        code: JsonErrorCode.preconditionFailed,
        exitCode: ExitCode.noPerm.code,
      );
    }

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

    final changed = member.role != role;
    if (changed) {
      final updateError = await guardApiCall(
        () => codePushClientWrapper.setEnterpriseMemberRole(
          enterpriseId: enterprise.id,
          userId: member.userId,
          role: role!,
        ),
        code: JsonErrorCode.softwareError,
        message: "Failed to change $label's enterprise role.",
      );
      if (updateError != null) return updateError;
    }

    if (isJsonMode) {
      emitJsonSuccess({
        'enterprise_id': enterprise.id,
        'user_id': member.userId,
        'email': member.email,
        'from_role': member.role.value,
        'to_role': role!.value,
        'changed': changed,
      });
      return ExitCode.success.code;
    }
    if (!changed) {
      logger.info(
        '$label is already ${role!.value} in "${enterprise.name}"; nothing '
        'changed.',
      );
      return ExitCode.success.code;
    }
    logger.success(
      'Changed $label from ${member.role.value} to ${role!.value} in '
      '"${enterprise.name}".',
    );
    return ExitCode.success.code;
  }
}
