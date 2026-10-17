import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template invitations_list_command}
/// `shorebird invitations list`
/// List the pending invitations sent to the current user.
/// {@endtemplate}
class InvitationsListCommand extends ShorebirdCommand {
  /// {@macro invitations_list_command}
  InvitationsListCommand();

  @override
  String get name => 'list';

  @override
  String get description =>
      'List the pending invitations sent to you.\n\n'
      'Example output (space-separated: id  name  kind  role  inviter  sent):\n'
      '  0b6c...  Acme Corp  organization  developer  admin@acme.com  '
      '2026-10-16\n\n'
      'Kind is "organization" or "app". Accept one with '
      '`shorebird invitations accept <id>`.\n\n'
      '${ShorebirdCommand.jsonHint('shorebird invitations list --json')}';

  @override
  Future<int> run() async {
    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
      );
    } on PreconditionFailedException catch (error) {
      return reportPreconditionFailure(error);
    }

    late final List<ReceivedInvitation> invitations;
    final fetchError = await guardApiCall(
      () async =>
          invitations = await codePushClientWrapper.getReceivedInvitations(),
      code: JsonErrorCode.fetchFailed,
      message: 'Failed to fetch invitations.',
    );
    if (fetchError != null) return fetchError;

    if (isJsonMode) {
      emitJsonSuccess({
        'invitations': [
          for (final invitation in invitations)
            {
              'id': invitation.id,
              'kind': invitation.kind,
              'organization_id': invitation.organizationId,
              'app_id': invitation.appId,
              'name': invitation.targetName,
              'role': invitation.role.name,
              'inviter_email': invitation.inviterEmail,
              'created_at': invitation.createdAt.toUtc().toIso8601String(),
              'expires_at': invitation.expiresAt.toUtc().toIso8601String(),
            },
        ],
      });
      return ExitCode.success.code;
    }

    if (invitations.isEmpty) {
      logger.info('No pending invitations.');
      return ExitCode.success.code;
    }

    for (final invitation in invitations) {
      final sent = invitation.createdAt.toUtc().toIso8601String().substring(
        0,
        10,
      );
      logger.info(
        '${invitation.id}  ${lightCyan.wrap(invitation.targetName)}  '
        '${invitation.kind}  ${invitation.role.name}  '
        '${invitation.inviterEmail}  $sent',
      );
    }
    return ExitCode.success.code;
  }
}

extension on ReceivedInvitation {
  /// What the invitation is to: "organization" or "app".
  String get kind => organizationId != null ? 'organization' : 'app';
}
