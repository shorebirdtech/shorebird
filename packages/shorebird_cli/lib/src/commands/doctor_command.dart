import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_environment.dart';
import 'package:shorebird_cli/src/shorebird_version_mixin.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:shorebird_cli/src/version.dart';

/// {@template doctor_command}
/// `shorebird doctor`
/// A command that checks for potential issues with the current shorebird
/// environment.
/// {@endtemplate}
class DoctorCommand extends ShorebirdCommand with ShorebirdVersionMixin {
  /// {@macro doctor_command}
  DoctorCommand({super.validators}) {
    validators.addAll(_doctorValidators);

    argParser.addFlag(
      'fix',
      abbr: 'f',
      help: 'Fix issues where possible.',
      negatable: false,
    );
  }

  late final List<Validator> _doctorValidators = [
    ShorebirdVersionValidator(
      isShorebirdVersionCurrent: isShorebirdVersionCurrent,
    ),
    ShorebirdFlutterValidator(),
    AndroidInternetPermissionValidator(),
  ];

  @override
  String get name => 'doctor';

  @override
  String get description => 'Show information about the installed tooling.';

  @override
  Future<int> run() async {
    final shouldFix = results['fix'] == true;
    final isInProject =
        ShorebirdEnvironment.getShorebirdYamlFile().existsSync();

    logger.info('''

Shorebird v$packageVersion
Shorebird Engine • revision ${ShorebirdEnvironment.shorebirdEngineRevision}''');

    final allIssues = <ValidationIssue>[];
    final allFixableIssues = <ValidationIssue>[];
    for (final validator in validators) {
      if (validator.scope == ValidatorScope.project && !isInProject) {
        continue;
      }

      final failedFixes = <ValidationIssue, dynamic>{};
      final progress = logger.progress(validator.description);
      final issues = await validator.validate(process);
      if (issues.isEmpty) {
        progress.complete();
        continue;
      }

      final fixableIssues = issues.where((issue) => issue.fix != null);
      var unresolvedIssues = issues;
      if (fixableIssues.isNotEmpty) {
        if (shouldFix) {
          // If --fix flag was used and there are fixable issues, fix them.
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
          unresolvedIssues = await validator.validate(process);
          if (unresolvedIssues.isEmpty) {
            final numFixed = issues.length - unresolvedIssues.length;
            final fixAppliedMessage =
                '($numFixed fix${numFixed == 1 ? '' : 'es'} applied)';
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

    logger.info('');

    if (allIssues.isEmpty) {
      logger.info('No issues detected!');
    } else {
      final numIssues = allIssues.length;
      logger.info('$numIssues issue${numIssues == 1 ? '' : 's'} detected.');

      if (allFixableIssues.isNotEmpty && !shouldFix) {
        final fixableIssueCount = allFixableIssues.length;
        logger.info(
          '''
$fixableIssueCount issue${fixableIssueCount == 1 ? '' : 's'} can be fixed automatically with ${lightCyan.wrap('shorebird doctor --fix')}.''',
        );
      }
    }

    return ExitCode.success.code;
  }
}
