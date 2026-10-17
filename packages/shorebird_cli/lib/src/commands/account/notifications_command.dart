import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';

/// {@template account_notifications_command}
/// `shorebird account notifications`
/// Show or change whether the current user gets email notifications.
/// {@endtemplate}
class AccountNotificationsCommand extends ShorebirdCommand {
  /// {@macro account_notifications_command}
  AccountNotificationsCommand() {
    argParser.addOption(
      emailOption,
      allowed: ['on', 'off'],
      help: 'Turn email notifications on or off.',
    );
  }

  /// The option that turns email notifications on or off.
  static const emailOption = 'email';

  @override
  String get name => 'notifications';

  @override
  String get description =>
      'Show or change whether Shorebird emails you.\n\n'
      'With no options, shows the setting. The emails Shorebird sends today '
      "are warnings that an app is near or over its plan's patch install "
      'limit.\n\n'
      'Examples:\n'
      '  shorebird account notifications\n'
      '  shorebird account notifications --email off\n\n'
      '${ShorebirdCommand.jsonHint('shorebird account notifications --json')}';

  @override
  Future<int> run() async {
    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
      );
    } on PreconditionFailedException catch (error) {
      return reportPreconditionFailure(error);
    }

    final requested = switch (results[emailOption] as String?) {
      'on' => true,
      'off' => false,
      _ => null,
    };

    late final bool enabled;
    final error = requested == null
        ? await guardApiCall(
            () async => enabled = await codePushClientWrapper
                .getEmailNotificationsEnabled(),
            code: JsonErrorCode.fetchFailed,
            message: 'Failed to fetch your notification settings.',
          )
        : await guardApiCall(
            () async {
              await codePushClientWrapper.setEmailNotificationsEnabled(
                enabled: requested,
              );
              enabled = requested;
            },
            code: JsonErrorCode.softwareError,
            message: 'Failed to update your notification settings.',
          );
    if (error != null) return error;

    if (isJsonMode) {
      emitJsonSuccess({'email': enabled});
      return ExitCode.success.code;
    }

    final state = enabled ? 'on' : 'off';
    if (requested == null) {
      logger.info('Email notifications: $state');
    } else {
      logger.success('Email notifications are now $state.');
    }
    return ExitCode.success.code;
  }
}
