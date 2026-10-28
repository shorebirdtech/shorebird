import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template whoami_command}
/// `shorebird account whoami`
/// Show the currently authenticated Shorebird user.
/// {@endtemplate}
class WhoamiCommand extends ShorebirdCommand {
  /// {@macro whoami_command}
  WhoamiCommand();

  @override
  String get name => 'whoami';

  @override
  String get description =>
      'Show the currently authenticated Shorebird user.\n\n'
      'Example output:\n'
      '  ID:             42\n'
      '  Email:          user@example.com\n'
      '  Display name:   Example User\n'
      '  Plan:           enterprise\n'
      '  Overage limit:  10000\n'
      '  Credential:     Login (shorebird login)\n\n'
      'Plan is your plan level: "free", "pro", "business" or "enterprise" '
      '("unknown" if the server does not report one).\n'
      'Overage limit is the max pay-as-you-go patch installs allowed '
      'beyond your plan ("none" if unset).\n'
      'Credential is how this command authenticated: an API key from '
      '$shorebirdTokenEnvVar, GitHub Actions OIDC, or your '
      '`shorebird login`.\n\n'
      '${ShorebirdCommand.jsonHint('shorebird account whoami --json')}';

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
    late final String? planLevel;
    final fetchError = await guardApiCall(
      () async {
        user = await codePushClientWrapper.getCurrentUser();
        planLevel = await codePushClientWrapper.getPlanLevel();
      },
      code: JsonErrorCode.fetchFailed,
      message: 'Failed to fetch account.',
    );
    if (fetchError != null) return fetchError;

    if (isJsonMode) {
      emitJsonSuccess({
        'user': {
          'id': user.id,
          'email': user.email,
          'display_name': user.displayName,
          // `plan` predates plan levels and is kept so existing scripts keep
          // working; `plan_level` is the finer-grained value. Any level but
          // free is paid, matching the server. Null when the server does
          // not report a level.
          'plan': switch (planLevel) {
            null => null,
            'free' => 'free',
            _ => 'paid',
          },
          'plan_level': planLevel,
          'overage_limit': user.patchOverageLimit,
        },
        'credential': auth.credentialKind?.jsonName,
      });
      return ExitCode.success.code;
    }

    logger
      ..info('ID:             ${user.id}')
      ..info('Email:          ${user.email}');
    if (user.displayName != null) {
      logger.info('Display name:   ${user.displayName}');
    }
    logger
      ..info('Plan:           ${planLevel ?? 'unknown'}')
      ..info('Overage limit:  ${user.patchOverageLimit ?? 'none'}');
    if (auth.credentialKind case final kind?) {
      logger.info('Credential:     ${kind.description}');
    }

    return ExitCode.success.code;
  }
}

/// {@template top_level_whoami_command}
/// `shorebird whoami`
/// A hidden alias of `shorebird account whoami`, the command agents guess.
/// {@endtemplate}
class TopLevelWhoamiCommand extends WhoamiCommand {
  /// {@macro top_level_whoami_command}
  TopLevelWhoamiCommand();

  @override
  bool get hidden => true;
}
