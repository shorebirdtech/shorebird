import 'dart:convert';

import 'package:mason_logger/mason_logger.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/validators/validators.dart';

/// A reference to a [Doctor] instance.
final doctorRef = create(Doctor.new);

/// The [Doctor] instance available in the current zone.
Doctor get doctor => read(doctorRef);

/// {@template doctor}
/// A class that provides a set of validators to check the current environment
/// for potential issues.
/// {@endtemplate}
class Doctor {
  /// Validators that verify shorebird will work on Android.
  final List<Validator> androidCommandValidators = [
    AndroidInternetPermissionValidator(),
  ];

  /// Validators that verify shorebird will work on iOS.
  final List<Validator> iosCommandValidators = [];

  /// Validators that verify shorebird will work on Windows.
  final List<Validator> linuxCommandValidators = [
    // Check whether powershell is installed?
  ];

  /// Validators that verify shorebird will work on macOS.
  final List<Validator> macosCommandValidators = [
    MacosEntitlementsValidator(),
  ];

  /// Validators that verify shorebird will work on Windows.
  final List<Validator> windowsCommandValidators = [
    // Check whether powershell is installed?
  ];

  /// Validators that should run on all commands.
  List<Validator> generalValidators = [
    ShorebirdVersionValidator(),
    AndroidInternetPermissionValidator(),
    MacosEntitlementsValidator(),
    ShorebirdYamlAssetValidator(),
    TrackedLockFilesValidator(),
  ];

  /// Run the provided [validators]. If [applyFixes] is `true`, any validation
  /// issues that can be automatically fixed will be.
  Future<void> runValidators(
    List<Validator> validators, {
    bool applyFixes = false,
  }) async {
    final allIssues = <ValidationIssue>[];
    final allFixableIssues = <ValidationIssue>[];

    var totalIssuesFixed = 0;
    for (final validator in validators) {
      if (!validator.canRunInCurrentContext()) {
        continue;
      }

      final failedFixes = <ValidationIssue, dynamic>{};
      final validatorProgress = logger.progress(validator.description);
      final issues = await validator.validate();
      if (issues.isEmpty) {
        validatorProgress.complete();
        continue;
      }

      final fixableIssues = issues.where((issue) => issue.fix != null);
      var unresolvedIssues = issues;
      if (fixableIssues.isNotEmpty) {
        if (applyFixes) {
          validatorProgress.update('Fixing');
          for (final issue in fixableIssues) {
            try {
              await issue.fix!();
            } on Exception catch (error) {
              failedFixes[issue] = error;
            }
          }

          // Re-run the validator to see if there are any remaining issues that
          // we couldn't fix.
          unresolvedIssues = await validator.validate();
          final numIssuesFixed = issues.length - unresolvedIssues.length;
          if (numIssuesFixed > 0) {
            totalIssuesFixed += numIssuesFixed;
            final fixAppliedMessage =
                '''($numIssuesFixed fix${numIssuesFixed == 1 ? '' : 'es'} applied)''';
            validatorProgress.complete(
              '''${validator.description} ${green.wrap(fixAppliedMessage)}''',
            );

            continue;
          }
        } else {
          allFixableIssues.addAll(issues);
        }
      }

      // The validator should only fail if there are errors (warnings don't
      // cause failure).
      final unresolvedErrors = unresolvedIssues.where(
        (issue) => issue.severity == ValidationIssueSeverity.error,
      );
      unresolvedErrors.isEmpty
          ? validatorProgress.complete()
          : validatorProgress.fail();

      for (final issue in failedFixes.keys) {
        logger.err(
          '''  An error occurred while attempting to fix ${issue.message}: ${failedFixes[issue]}''',
        );
      }

      for (final issue in unresolvedIssues) {
        if (issue.displayMessage == null) {
          continue;
        }

        final lines = const LineSplitter().convert(issue.displayMessage!);
        for (final (i, line) in lines.indexed) {
          var leadingPaddingSpaceCount = 2;
          if (i > 0) {
            // Indent subsequent lines to align with the first line after the
            // leading string and the space following it.
            leadingPaddingSpaceCount += issue.severity.rawLeading.length + 1;
          }
          logger.info('${' ' * leadingPaddingSpaceCount}$line');
        }
      }

      allIssues.addAll(unresolvedIssues);
    }

    if (totalIssuesFixed > 0) {
      return;
    }

    if (allIssues.isEmpty) {
      logger.info('''

No issues detected!''');
    } else {
      final numIssues = allIssues.length;
      logger.info('$numIssues issue${numIssues == 1 ? '' : 's'} detected.');

      if (allFixableIssues.isNotEmpty && !applyFixes) {
        final fixableIssueCount = allFixableIssues.length;
        logger.info(
          '''
$fixableIssueCount issue${fixableIssueCount == 1 ? '' : 's'} can be fixed automatically with ${lightCyan.wrap('shorebird doctor --fix')}.''',
        );
      }
    }
  }
}
