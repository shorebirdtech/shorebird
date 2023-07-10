import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';
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

mixin ShorebirdValidationMixin on ShorebirdConfigMixin {
  /// Checks common preconditions for running a command and throws an
  /// appropriate [PreconditionFailedException] if any of them fail.
  Future<void> validatePreconditions({
    bool checkShorebirdInitialized = false,
    bool checkUserIsAuthenticated = false,
    bool checkValidators = false,
  }) async {
    if (checkUserIsAuthenticated && !auth.isAuthenticated) {
      logger
        ..err('You must be logged in to run this command.')
        ..info(
          '''If you already have an account, run ${lightCyan.wrap('shorebird login')} to sign in.''',
        )
        ..info(
          '''If you don't have a Shorebird account, run ${lightCyan.wrap('shorebird account create')} to create one.''',
        );
      throw UserNotAuthorizedException();
    }

    if (checkShorebirdInitialized && !isShorebirdInitialized) {
      logger.err(
        'Shorebird is not initialized. Did you run "shorebird init"?',
      );
      throw ShorebirdNotInitializedException();
    }

    if (checkValidators) {
      final validationIssues = await runValidators();
      if (validationIssuesContainsError(validationIssues)) {
        logValidationFailure(issues: validationIssues);
        throw ValidationFailedException();
      }
    }
  }

  /// Runs [Validator.validate] on all [validators] and writes results to
  /// stdout.
  Future<List<ValidationIssue>> runValidators() async {
    final validationIssues = (await Future.wait(
      validators.map((v) => v.validate(process)),
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
