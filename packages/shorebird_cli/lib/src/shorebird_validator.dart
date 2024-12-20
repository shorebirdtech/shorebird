import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/validators/validators.dart';

/// An exception thrown when a precondition for running a command is not met.
abstract interface class PreconditionFailedException implements Exception {
  /// The exit code to use when the precondition fails.
  ExitCode get exitCode;
}

/// An exception thrown when Shorebird has not been initialized.
class ShorebirdNotInitializedException implements PreconditionFailedException {
  @override
  ExitCode get exitCode => ExitCode.config;
}

/// An exception thrown when the user is not authorized to run a command.
class UserNotAuthorizedException implements PreconditionFailedException {
  @override
  ExitCode get exitCode => ExitCode.noUser;
}

/// An exception thrown when validation fails.
class ValidationFailedException implements PreconditionFailedException {
  @override
  ExitCode get exitCode => ExitCode.config;
}

/// An exception thrown when a command is run in an unsupported context.
class UnsupportedContextException implements PreconditionFailedException {
  // coverage:ignore-start
  @override
  ExitCode get exitCode => ExitCode.unavailable;
  // coverage:ignore-end
}

/// An exception thrown when the operating system is not supported.
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
        throw ShorebirdNotInitializedException();
      }
    }

    for (final validator in validators) {
      if (!validator.canRunInCurrentContext()) {
        logger.err(validator.incorrectContextMessage);
        throw UnsupportedContextException();
      }
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

  /// Runs [FlavorValidator] and throws a [ValidationFailedException] if any
  /// issues are found.
  Future<void> validateFlavors({required String? flavorArg}) async {
    final flavorValidator = FlavorValidator(flavorArg: flavorArg);
    final issues = await flavorValidator.validate();
    if (validationIssuesContainsError(issues)) {
      for (final issue in issues) {
        logger.err(issue.message);
      }

      throw ValidationFailedException();
    }
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
