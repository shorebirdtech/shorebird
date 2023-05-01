import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/command.dart';
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
  DoctorCommand({
    required super.logger,
    super.validators,
  }) {
    validators = _allValidators(baseValidators: validators);

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

    logger.info('''

Shorebird v$packageVersion
Shorebird Engine • revision ${ShorebirdEnvironment.shorebirdEngineRevision}''');

    final allIssues = <ValidationIssue>[];
    for (final validator in validators) {
      final progress = logger.progress(validator.description);
      var issues = await validator.validate(process);
      final fixableIssues = issues.where((issue) => issue.fix != null);
      if (shouldFix && fixableIssues.isNotEmpty) {
        for (final issue in fixableIssues) {
          await issue.fix!();
        }
        // Re-run validator to ensure that fixes worked.
        issues = await validator.validate(process);
      }

      allIssues.addAll(issues);
      if (issues.isEmpty) {
        progress.complete();
      } else {
        progress.fail();

        for (final issue in issues) {
          logger.info('  ${issue.displayMessage}');
        }
      }
    }

    logger.info('');

    if (allIssues.isEmpty) {
      logger.info('No issues detected!');
    } else {
      final numIssues = allIssues.length;
      logger.info('$numIssues issue${numIssues == 1 ? '' : 's'} detected.');

      final issuesWithFix = allIssues.where((issue) => issue.fix != null);
      if (issuesWithFix.isNotEmpty && !shouldFix) {
        logger.info(
          '''
We can fix some of these issues for you. Run ${lightCyan.wrap('shorebird doctor --fix')} to fix''',
        );
      }
    }

    return ExitCode.success.code;
  }

  /// Creates a list that is the union of [baseValidators] and
  /// [_doctorValidators].
  List<Validator> _allValidators({
    required List<Validator> baseValidators,
  }) {
    final missingValidators = _doctorValidators
        .where(
          (doctorValidator) => baseValidators.none(
            (baseValidator) => baseValidator.id == doctorValidator.id,
          ),
        )
        .toList();

    return baseValidators + missingValidators;
  }
}
