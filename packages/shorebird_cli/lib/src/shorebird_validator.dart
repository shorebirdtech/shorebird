import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/validators/validators.dart';

abstract interface class PreconditionFailedException implements Exception {
  ExitCode get exitCode;
}

class ShorebirdNotInitializedException implements PreconditionFailedException {
  @override
  ExitCode get exitCode => ExitCode.config;
}

class UserNotAuthorizedException implements PreconditionFailedException {
  @override
  ExitCode get exitCode => ExitCode.noUser;
}

class ValidationFailedException implements PreconditionFailedException {
  @override
  ExitCode get exitCode => ExitCode.config;
}

class UnsupportedOperatingSystemException
    implements PreconditionFailedException {
  @override
  ExitCode get exitCode => ExitCode.unavailable;
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
      logger.err(
        '''This command is only supported on ${supportedOperatingSystems.join(' ,')}.''',
      );
      throw UnsupportedOperatingSystemException();
    }

    if (checkUserIsAuthenticated && !auth.isAuthenticated) {
      logger
        ..err('You must be logged in to run this command.')
        ..info(
          '''If you already have an account, run ${lightCyan.wrap('shorebird login')} to sign in.''',
        )
        ..info(
          '''If you don't have a Shorebird account, go to ${lightCyan.wrap('https://console.shorebird.dev')} to create one.''',
        );
      throw UserNotAuthorizedException();
    }

    if (checkShorebirdInitialized && !shorebirdEnv.isShorebirdInitialized) {
      logger.err(
        'Shorebird is not initialized. Did you run "shorebird init"?',
      );
      throw ShorebirdNotInitializedException();
    }

    final validationIssues = await runValidators(validators);
    if (validationIssuesContainsError(validationIssues)) {
      logValidationFailure(issues: validationIssues);
      throw ValidationFailedException();
    }
  }

  /// Runs [Validator.validate] on all [validators] and writes results to
  /// stdout.
  Future<List<ValidationIssue>> runValidators(
    List<Validator> validators,
  ) async {
    final validationIssues = (await Future.wait(
      validators.map((v) => v.validate()),
    ))
        .flattened
        .toList();

    for (final issue in validationIssues) {
      logger.info(issue.displayMessage);
    }

    return validationIssues;
  }

  /// Whether any [ValidationIssue]s have a severity of
  /// [ValidationIssueSeverity.error].
  bool validationIssuesContainsError(List<ValidationIssue> issues) =>
      issues.any((issue) => issue.severity == ValidationIssueSeverity.error);

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
