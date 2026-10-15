import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/auth/github_actions_oidc.dart';
import 'package:shorebird_cli/src/auth/oidc_credential_source.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// An exception thrown when a precondition for running a command is not met.
///
/// The human-readable explanation has already been logged by the time this is
/// thrown. [message] and [hint] carry the same explanation as plain text, for
/// output that isn't the terminal (`--json`).
abstract interface class PreconditionFailedException implements Exception {
  /// The exit code to use when the precondition fails.
  ExitCode get exitCode;

  /// What failed, as plain text.
  String get message;

  /// How to fix it, as plain text, if there is a known fix.
  String? get hint;
}

/// {@template precondition_failed_exit}
/// A [ProcessExit] for a failed precondition, carrying the [failure] so the
/// command runner can report why with `--json` instead of just the exit code.
/// {@endtemplate}
class PreconditionFailedExit extends ProcessExit {
  /// {@macro precondition_failed_exit}
  PreconditionFailedExit(this.failure) : super(failure.exitCode.code);

  /// The precondition that failed.
  final PreconditionFailedException failure;
}

/// An exception thrown when Shorebird has not been initialized.
class ShorebirdNotInitializedException implements PreconditionFailedException {
  /// Creates a [ShorebirdNotInitializedException].
  ShorebirdNotInitializedException({
    this.message =
        'Unable to find shorebird.yaml. Are you in a shorebird app directory?',
    this.hint =
        'If you have not yet initialized your app, run `shorebird init` to '
        'get started.',
  });

  @override
  ExitCode get exitCode => ExitCode.config;

  @override
  final String message;

  @override
  final String? hint;
}

/// An exception thrown when the user is not authorized to run a command.
class UserNotAuthorizedException implements PreconditionFailedException {
  /// Creates a [UserNotAuthorizedException].
  UserNotAuthorizedException({
    this.message = 'You must be logged in to run this command.',
    this.hint =
        'If you already have an account, run `shorebird login` to sign in. '
        "If you don't have a Shorebird account, go to "
        'https://console.shorebird.dev to create one.',
  });

  @override
  ExitCode get exitCode => ExitCode.noUser;

  @override
  final String message;

  @override
  final String? hint;
}

/// An exception thrown when validation fails.
class ValidationFailedException implements PreconditionFailedException {
  /// Creates a [ValidationFailedException].
  ValidationFailedException({
    this.message = 'Aborting due to validation errors.',
    this.hint,
  });

  @override
  ExitCode get exitCode => ExitCode.config;

  @override
  final String message;

  @override
  final String? hint;
}

/// An exception thrown when a command is run in an unsupported context.
class UnsupportedContextException implements PreconditionFailedException {
  /// Creates an [UnsupportedContextException].
  UnsupportedContextException({
    this.message = 'This command cannot run in the current context.',
    this.hint,
  });

  // coverage:ignore-start
  @override
  ExitCode get exitCode => ExitCode.unavailable;
  // coverage:ignore-end

  @override
  final String message;

  @override
  final String? hint;
}

/// An exception thrown when the operating system is not supported.
class UnsupportedOperatingSystemException
    implements PreconditionFailedException {
  /// Creates an [UnsupportedOperatingSystemException].
  UnsupportedOperatingSystemException({
    this.message = 'This command is not supported on this operating system.',
    this.hint,
  });

  @override
  ExitCode get exitCode => ExitCode.unavailable;

  @override
  final String message;

  @override
  final String? hint;
}

/// A reference to a [ShorebirdValidator] instance.
final shorebirdValidatorRef = create(ShorebirdValidator.new);

/// The [ShorebirdValidator] instance available in the current zone.
ShorebirdValidator get shorebirdValidator => read(shorebirdValidatorRef);

/// {@template shorebird_validator}
/// A class that provides common validation functionality for commands.
/// {@endtemplate}
class ShorebirdValidator {
  /// {@macro shorebird_validator}
  const ShorebirdValidator();

  /// Checks common preconditions for running a command and throws an
  /// appropriate [PreconditionFailedException] if any of them fail.
  Future<void> validatePreconditions({
    bool checkShorebirdInitialized = false,
    bool checkUserIsAuthenticated = false,
    List<Validator> validators = const [],
    Set<String>? supportedOperatingSystems,
  }) async {
    if (supportedOperatingSystems != null &&
        !supportedOperatingSystems.contains(platform.operatingSystem)) {
      final message =
          '''This command is only supported on ${supportedOperatingSystems.join(', ')} (this machine is running ${platform.operatingSystem}).''';
      logger.err(message);
      throw UnsupportedOperatingSystemException(message: message);
    }

    if (checkUserIsAuthenticated && !auth.isAuthenticated) {
      // Such as a GitHub Actions job granted an OIDC token without
      // SHOREBIRD_PROJECT_ID.
      if (auth.unavailableCredentialsReason case final reason?) {
        logger.err(reason.message);
        if (reason.hint case final hint?) logger.info(hint);
        throw UserNotAuthorizedException(
          message: reason.message,
          hint: reason.hint,
        );
      }
    }

    if (checkUserIsAuthenticated &&
        !auth.isAuthenticated &&
        platform.environment[githubActionsEnvVar] == 'true') {
      // Neither SHOREBIRD_TOKEN nor the ID token request variables GitHub
      // sets for a job granted `permissions: id-token: write`.
      const oidcHint =
          'To sign in from GitHub Actions without a stored secret, grant the '
          'job `permissions: id-token: write`, set $shorebirdProjectIdEnvVar '
          'to the id of your project, and add a GitHub Actions trust rule for '
          'this workflow at https://console.shorebird.dev.';
      const apiKeyHint =
          'Or set $shorebirdTokenEnvVar to a Shorebird API key from '
          'https://console.shorebird.dev.';
      logger
        ..err('You must be logged in to run this command.')
        ..info(oidcHint)
        ..info(apiKeyHint);
      throw UserNotAuthorizedException(hint: '$oidcHint $apiKeyHint');
    }

    if (checkUserIsAuthenticated && !auth.isAuthenticated) {
      logger
        ..err('You must be logged in to run this command.')
        ..info(
          '''If you already have an account, run ${lightCyan.wrap('shorebird login')} to sign in.''',
        )
        ..info(
          '''If you don't have a Shorebird account, go to ${link(uri: Uri.parse('https://console.shorebird.dev'))} to create one.''',
        );
      throw UserNotAuthorizedException();
    }

    if (checkShorebirdInitialized) {
      if (!shorebirdEnv.hasShorebirdYaml) {
        logger
          ..err(
            '''Unable to find shorebird.yaml. Are you in a shorebird app directory?''',
          )
          ..info(
            '''If you have not yet initialized your app, run ${lightCyan.wrap('shorebird init')} to get started.''',
          );
        throw ShorebirdNotInitializedException();
      }

      if (!shorebirdEnv.pubspecContainsShorebirdYaml) {
        logger
          ..err(
            '''Your pubspec.yaml does not have shorebird.yaml as a flutter asset.''',
          )
          ..info('''
To fix, update your pubspec.yaml to include the following:

  flutter:
    assets:
      - shorebird.yaml # Add this line
''');
        throw ShorebirdNotInitializedException(
          message:
              'Your pubspec.yaml does not have shorebird.yaml as a flutter '
              'asset.',
          hint:
              'Add shorebird.yaml to the flutter assets in your pubspec.yaml.',
        );
      }
    }

    for (final validator in validators) {
      if (!validator.canRunInCurrentContext()) {
        final message = validator.incorrectContextMessage;
        logger.err(message);
        throw message == null
            ? UnsupportedContextException()
            : UnsupportedContextException(message: message);
      }
    }

    final validationIssues = await runValidators(validators);
    if (validationIssuesContainsError(validationIssues)) {
      logValidationFailure(issues: validationIssues);
      throw _validationFailed(validationIssues);
    }
  }

  /// Runs [Validator.validate] on all [validators] and writes results to
  /// stdout.
  Future<List<ValidationIssue>> runValidators(
    List<Validator> validators,
  ) async {
    final validationIssues = (await Future.wait(
      validators.map((v) => v.validate()),
    )).flattened.toList();

    for (final issue in validationIssues) {
      logger.info(issue.displayMessage);
    }

    return validationIssues;
  }

  /// Runs [FlavorValidator] and throws a [ValidationFailedException] if any
  /// issues are found.
  Future<void> validateFlavors({
    required String? flavorArg,
    required ReleasePlatform releasePlatform,
  }) async {
    if (!releasePlatform.supportsFlavors) {
      if (flavorArg != null) {
        logger
          ..err('Flavors are not supported on this platform.')
          ..info(
            '''Please re-run this command without the --flavor argument. The app id ${lightCyan.wrap(shorebirdEnv.getShorebirdYaml()!.appId)} will be used.''',
          );

        throw ValidationFailedException(
          message: 'Flavors are not supported on this platform.',
          hint:
              'Re-run this command without the --flavor argument. The app id '
              '${shorebirdEnv.getShorebirdYaml()!.appId} will be used.',
        );
      }

      return;
    }

    final flavorValidator = FlavorValidator(flavorArg: flavorArg);
    final issues = await flavorValidator.validate();
    if (validationIssuesContainsError(issues)) {
      for (final issue in issues) {
        logger.err(issue.message);
      }

      throw ValidationFailedException(
        message: _errorMessages(issues).join(' '),
      );
    }

    if (validationIssuesContainsWarning(issues)) {
      for (final issue in issues) {
        logger.warn(issue.message);
      }
    }
  }

  /// Whether any [ValidationIssue]s have a severity of
  /// [ValidationIssueSeverity.error].
  bool validationIssuesContainsError(List<ValidationIssue> issues) =>
      issues.any((issue) => issue.severity == ValidationIssueSeverity.error);

  /// Whether any [ValidationIssue]s have a severity of
  /// [ValidationIssueSeverity.warning].
  bool validationIssuesContainsWarning(List<ValidationIssue> issues) =>
      issues.any((issue) => issue.severity == ValidationIssueSeverity.warning);

  /// The [ValidationFailedException] for [issues]: the error messages and, if
  /// any issue can be fixed automatically, how.
  ValidationFailedException _validationFailed(List<ValidationIssue> issues) {
    final fixableCount = issues.where((issue) => issue.fix != null).length;
    return ValidationFailedException(
      message: [
        'Aborting due to validation errors.',
        ..._errorMessages(issues),
      ].join(' '),
      hint: fixableCount == 0
          ? null
          : '$fixableCount issue${fixableCount == 1 ? '' : 's'} can be fixed '
                'automatically with `shorebird doctor --fix`.',
    );
  }

  Iterable<String> _errorMessages(List<ValidationIssue> issues) => issues
      .where((issue) => issue.severity == ValidationIssueSeverity.error)
      .map((issue) => issue.message);

  /// Logs a message indicating that validation failed. If any of the issues
  /// can be automatically fixed, this also prompts the user to run
  /// `shorebird doctor --fix`.
  void logValidationFailure({required List<ValidationIssue> issues}) {
    logger.err('Aborting due to validation errors.');

    final fixableIssues = issues.where((issue) => issue.fix != null);
    if (fixableIssues.isNotEmpty) {
      logger.info(
        '''${fixableIssues.length} issue${fixableIssues.length == 1 ? '' : 's'} can be fixed automatically with ${lightCyan.wrap('shorebird doctor --fix')}.''',
      );
    }
  }
}
