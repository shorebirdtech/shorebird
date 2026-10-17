import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';

/// {@template account_update_command}
/// `shorebird account update`
/// Change the current user's profile.
/// {@endtemplate}
class AccountUpdateCommand extends ShorebirdCommand {
  /// {@macro account_update_command}
  AccountUpdateCommand() {
    argParser.addOption(
      nameOption,
      valueHelp: 'display name',
      help: 'Your new display name.',
    );
  }

  /// The option that sets the display name.
  static const nameOption = 'name';

  @override
  String get name => 'update';

  @override
  String get description =>
      'Change your display name.\n\n'
      'Example:\n'
      '  shorebird account update --name "Jane Doe"\n\n'
      '${ShorebirdCommand.jsonHint(
        'shorebird account update --name "Jane Doe" --json',
      )}';

  @override
  Future<int> run() async {
    final displayName = (results[nameOption] as String?)?.trim();
    if (displayName == null || displayName.isEmpty) {
      return reportError(
        message: 'Nothing to update: pass --$nameOption.',
        hint: 'Run: shorebird account update --$nameOption "<display name>"',
      );
    }

    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
      );
    } on PreconditionFailedException catch (error) {
      return reportPreconditionFailure(error);
    }

    final updateError = await guardApiCall(
      () => codePushClientWrapper.updateCurrentUser(displayName: displayName),
      code: JsonErrorCode.softwareError,
      message: 'Failed to update your account.',
    );
    if (updateError != null) return updateError;

    if (isJsonMode) {
      emitJsonSuccess({
        'user': {'display_name': displayName},
      });
      return ExitCode.success.code;
    }

    logger.success('Your display name is now "$displayName".');
    return ExitCode.success.code;
  }
}
