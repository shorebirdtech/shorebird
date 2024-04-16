import 'package:mason_logger/mason_logger.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/logger.dart';
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

  /// All available validators.
  List<Validator> allValidators = [
    ShorebirdVersionValidator(),
    ShorebirdFlutterValidator(),
    AndroidInternetPermissionValidator(),
    StorageAccessValidator(),
    ShorebirdYAMLAssetValidator(),
  ];

  /// Run the provided [validators]. If [applyFixes] is `true`, any validation
  /// issues that can be automatically fixed will be.
  Future<void> runValidators(
    List<Validator> validators, {
    bool applyFixes = false,
  }) async {
    final allIssues = <ValidationIssue>[];
    final allFixableIssues = <ValidationIssue>[];

    var numIssuesFixed = 0;
    for (final validator in validators) {
      if (!validator.canRunInCurrentContext()) {
        continue;
      }

      final failedFixes = <ValidationIssue, dynamic>{};
      final progress = logger.progress(validator.description);
      final issues = await validator.validate();
      if (issues.isEmpty) {
        progress.complete();
        continue;
      }

      final fixableIssues = issues.where((issue) => issue.fix != null);
      var unresolvedIssues = issues;
      if (fixableIssues.isNotEmpty) {
        if (applyFixes) {
          progress.update('Fixing');
          for (final issue in fixableIssues) {
            try {
              await issue.fix!();
            } catch (error) {
              failedFixes[issue] = error;
            }
          }

          // Re-run the validator to see if there are any remaining issues that
          // we couldn't fix.
          unresolvedIssues = await validator.validate();
          if (unresolvedIssues.isEmpty) {
            numIssuesFixed += issues.length - unresolvedIssues.length;
            final fixAppliedMessage =
                '''($numIssuesFixed fix${numIssuesFixed == 1 ? '' : 'es'} applied)''';
            progress.complete(
              '''${validator.description} ${green.wrap(fixAppliedMessage)}''',
            );
            continue;
          }
        } else {
          allFixableIssues.addAll(issues);
        }
      }

      progress.fail(validator.description);

      for (final issue in failedFixes.keys) {
        logger.err(
          '''  An error occurred while attempting to fix ${issue.message}: ${failedFixes[issue]}''',
        );
      }

      for (final issue in unresolvedIssues) {
        logger.info('  ${issue.displayMessage}');
      }

      allIssues.addAll(unresolvedIssues);
    }

    if (numIssuesFixed > 0) {
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
