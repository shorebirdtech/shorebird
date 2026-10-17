import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/invitations/invitation_error_hints.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';

/// {@template invitations_accept_command}
/// `shorebird invitations accept <id>`
/// Accept an invitation sent to the current user.
/// {@endtemplate}
class InvitationsAcceptCommand extends InvitationResponseCommand {
  /// {@macro invitations_accept_command}
  InvitationsAcceptCommand();

  @override
  String get name => 'accept';

  @override
  String get description =>
      'Accept an invitation sent to you, joining its organization or app '
      'with its role.\n\n'
      'Find the id with `shorebird invitations list`.\n\n'
      'Example output:\n'
      '  Accepted invitation 0b6c....\n'
      '  See it with `shorebird account orgs` or `shorebird apps list`.\n\n'
      '${ShorebirdCommand.jsonHint(
        'shorebird invitations accept <id> --json',
      )}';

  @override
  String get _pastTense => 'accepted';

  @override
  String get _nextStep =>
      'See it with `shorebird account orgs` or `shorebird apps list`.';

  @override
  Future<void> _respond(String invitationId) =>
      codePushClientWrapper.acceptInvitation(invitationId: invitationId);
}

/// {@template invitations_decline_command}
/// `shorebird invitations decline <id>`
/// Decline an invitation sent to the current user.
/// {@endtemplate}
class InvitationsDeclineCommand extends InvitationResponseCommand {
  /// {@macro invitations_decline_command}
  InvitationsDeclineCommand();

  @override
  String get name => 'decline';

  @override
  String get description =>
      'Decline an invitation sent to you.\n\n'
      'Find the id with `shorebird invitations list`.\n\n'
      'Example output:\n'
      '  Declined invitation 0b6c....\n\n'
      '${ShorebirdCommand.jsonHint(
        'shorebird invitations decline <id> --json',
      )}';

  @override
  String get _pastTense => 'declined';

  @override
  Future<void> _respond(String invitationId) =>
      codePushClientWrapper.declineInvitation(invitationId: invitationId);
}

/// {@template invitation_response_command}
/// A command that answers one invitation sent to the current user, named
/// by its id.
/// {@endtemplate}
abstract class InvitationResponseCommand extends ShorebirdCommand {
  /// {@macro invitation_response_command}
  InvitationResponseCommand();

  @override
  String get invocation => 'shorebird invitations $name <id>';

  /// The answer as it reads after the fact, e.g. "accepted".
  String get _pastTense;

  /// Sends the answer to the invitation with [invitationId].
  Future<void> _respond(String invitationId);

  /// What to run next after answering, if anything.
  String? get _nextStep => null;

  @override
  Future<int> run() async {
    if (results.rest.length != 1) {
      usageException(
        'Expected exactly one invitation <id>, got ${results.rest.length}. '
        'Find it with `shorebird invitations list`.',
      );
    }
    final invitationId = results.rest.single;

    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
      );
    } on PreconditionFailedException catch (error) {
      return reportPreconditionFailure(error);
    }

    final responseError = await withInvitationErrorHints(
      () => guardApiCall(
        () => _respond(invitationId),
        code: JsonErrorCode.softwareError,
        message: 'Failed to $name invitation $invitationId.',
      ),
    );
    if (responseError != null) return responseError;

    if (isJsonMode) {
      emitJsonSuccess({'invitation_id': invitationId, 'status': _pastTense});
      return ExitCode.success.code;
    }

    final verb = '${_pastTense[0].toUpperCase()}${_pastTense.substring(1)}';
    logger.success('$verb invitation $invitationId.');
    if (_nextStep case final nextStep?) logger.info(nextStep);
    return ExitCode.success.code;
  }
}
