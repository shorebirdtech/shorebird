import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/confirm_delete.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template account_delete_command}
/// `shorebird account delete`
/// Permanently delete the current user's account.
/// {@endtemplate}
class AccountDeleteCommand extends ShorebirdCommand with ConfirmDelete {
  /// {@macro account_delete_command}
  AccountDeleteCommand() {
    addConfirmDeleteOptions(
      style: DeleteConfirmationStyle.typeName,
      nameDescription: "Your account's email address",
    );
  }

  @override
  String get name => 'delete';

  @override
  String get description =>
      'Permanently deletes your Shorebird account.\n\n'
      'Your personal organization and every app in it, with all of their '
      'releases and patches, are deleted too, and you are removed from every '
      'team you belong to. This cannot be undone. The server refuses while '
      'you own a team organization or have an active subscription; transfer '
      'or delete the organization, or cancel the subscription, first.\n\n'
      'In a terminal, asks you to type your email address to confirm. When '
      'not running interactively (no terminal, CI, or --json), pass it with '
      '--$confirmNameArgName instead; there is no --$yesArgName.\n\n'
      '${ShorebirdCommand.jsonHint(
        'shorebird account delete --confirm-name "<email>" --json',
      )}';

  @override
  Future<int> run() async {
    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
      );
    } on PreconditionFailedException catch (error) {
      return reportPreconditionFailure(error);
    }

    late final PrivateUser user;
    final fetchError = await guardApiCall(
      () async => user = await codePushClientWrapper.getCurrentUser(),
      code: JsonErrorCode.fetchFailed,
      message: 'Failed to fetch account.',
    );
    if (fetchError != null) return fetchError;

    final gateErrorCode = confirmDelete(
      name: user.email,
      description: 'your Shorebird account (${user.email})',
      consequence:
          'This permanently deletes the Shorebird account ${user.email}, its '
          'personal organization, and every app in it with all of their '
          'releases and patches. Devices running those apps stop getting '
          'patches.',
    );
    if (gateErrorCode != null) return gateErrorCode;

    final deleteError = await guardApiCall(
      codePushClientWrapper.deleteCurrentUser,
      code: JsonErrorCode.softwareError,
      message: 'Failed to delete your account.',
    );
    if (deleteError != null) return deleteError;

    // A stored login now names a user that no longer exists.
    final loggedOut = auth.credentialKind == CredentialKind.login;
    if (loggedOut) auth.clearCredentials();

    if (isJsonMode) {
      emitJsonSuccess({
        'user': {'id': user.id, 'email': user.email},
        'deleted': true,
        'logged_out': loggedOut,
      });
      return ExitCode.success.code;
    }

    logger.success('Deleted the Shorebird account ${user.email}.');
    if (loggedOut) logger.info('You are now logged out.');
    return ExitCode.success.code;
  }
}
