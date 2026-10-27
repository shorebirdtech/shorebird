import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/members/member_target.dart';
import 'package:shorebird_cli/src/commands/orgs/organization_scoped_command.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template members_add_command}
/// `shorebird orgs members add <email>`
/// Invite someone to an organization.
/// {@endtemplate}
class MembersAddCommand extends ShorebirdCommand
    with OrganizationScopedCommand {
  /// {@macro members_add_command}
  MembersAddCommand() {
    argParser.addOption(
      'role',
      help: memberRoleHelp,
      defaultsTo: Role.developer.value,
    );
    addOrganizationScopeOption();
  }

  @override
  String get name => 'add';

  @override
  List<String> get aliases => const ['invite'];

  @override
  String get invocation => 'shorebird orgs members add <email>';

  @override
  String get description =>
      'Invites someone to an organization by email. They join once they '
      'accept (`shorebird invitations accept`, or the emailed link); the '
      'invitation expires after 14 days.\n\n'
      'Example output:\n'
      '  Invited bob@acme.com to "Acme Corp" as developer.\n\n'
      '${ShorebirdCommand.jsonHint(
        'shorebird orgs members add bob@acme.com --role admin --org-id 42 '
        '--json',
      )}';

  @override
  Future<int> run() async {
    final rest = results.rest;
    if (rest.length != 1) {
      return reportError(
        message:
            'Name one email to invite: '
            'shorebird orgs members add bob@acme.com.',
      );
    }
    final email = rest.single.trim();
    if (!email.contains('@')) {
      return reportError(message: '"$email" is not an email address.');
    }
    final (:role, error: roleError) = parseMemberRole(
      results['role'] as String,
    );
    if (roleError != null) return reportError(message: roleError);

    final (:membership, :errorCode) = await resolveOrganization();
    if (errorCode != null) return errorCode;
    final organization = membership!.organization;

    late final CreateOrganizationInvitation201Response response;
    final inviteError = await guardApiCall(
      () async =>
          response = await codePushClientWrapper.createOrganizationInvitation(
            organizationId: organization.id,
            email: email,
            role: role!,
          ),
      code: JsonErrorCode.softwareError,
      message: 'Failed to invite $email to organization ${organization.id}.',
    );
    if (inviteError != null) return inviteError;

    final (status, verb) = switch (response) {
      CreateInvitationResponse() => ('invited', 'Invited'),
      // The server adds an account its enterprise directory already has.
      AddedMemberResponse() => ('member', 'Added'),
    };

    if (isJsonMode) {
      emitJsonSuccess({
        'organization_id': organization.id,
        'email': email,
        'role': role!.value,
        'status': status,
      });
      return ExitCode.success.code;
    }

    logger.success(
      '$verb $email to "${organization.name}" as ${role!.value}.',
    );
    return ExitCode.success.code;
  }
}
